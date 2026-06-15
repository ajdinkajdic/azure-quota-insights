<#
.SYNOPSIS
    Exhaustive Azure quota and usage report across subscriptions, regions and
    every resource provider that exposes a usages or quotas endpoint.

.DESCRIPTION
    Coverage layers (each row is tagged in the Source column):

      1. Microsoft.Quota                            (unified quota / usage)
      2. Per-provider /locations/{region}/usages    (regional)
      3. Per-provider /usages                       (subscription scope)
      4. Per-provider /locations/{region}/quotas    (regional)
      5. Resource-scoped /usages and /quotas        (namespace, vault,
                                                    workspace, account, etc.)
      6. Azure Resource Graph inventory fallback    (any deployed ARM type)

    Layers 2-5 are populated by DYNAMIC DISCOVERY against the ARM provider
    catalog (Microsoft.Resources providers metadata). Any resource provider
    that publishes a "usages" or "quotas" resource type is queried
    automatically -- no need to maintain a hand-curated list.

    A curated KnownResourceScopedUsages map below handles the
    parent/child endpoints that ARM does not advertise as standalone
    resource types (for example serviceBus namespaces/usages,
    batch accounts/quotas, recoveryServices vaults/usages).

.PARAMETER SubscriptionIds
    Optional. Limit to these subscription IDs. Defaults to all subscriptions
    in the current tenant.

.PARAMETER Regions
    Optional. Limit to these regions. Defaults to every region returned by
    Get-AzLocation.

.PARAMETER OutputPath
    Output CSV path. Defaults to .\AzureQuotaUsage_Composite.csv

.PARAMETER IncludeZeroUsage
    Include rows where both QuotaApproved and UsageCurrent are zero or null.

.PARAMETER SkipResourceScopedUsages
    Skip layer 5 (per-namespace / per-vault / per-workspace usages).
    Big subscriptions can produce thousands of these calls; turn off if
    you only care about subscription and regional level numbers.

.PARAMETER SkipResourceGraphInventory
    Skip layer 6 (ARG inventory fallback).

.PARAMETER MaxParallelRegions
    Reserved for future PowerShell 7 ForEach-Object -Parallel use.

.NOTES
    Required modules:
      Az.Accounts
      Az.ResourceGraph
      Az.Resources

    Login first with Connect-AzAccount.

    The script tolerates 404 / 400 / 403 responses silently because not
    every RP supports every region or every scope.
#>

[CmdletBinding()]
param(
    [string[]] $SubscriptionIds,
    [string[]] $Regions,
    [string]   $OutputPath = ".\AzureQuotaUsage_Composite.csv",
    [switch]   $IncludeZeroUsage,
    [switch]   $SkipResourceScopedUsages,
    [switch]   $SkipResourceGraphInventory,
    [switch]   $SkipStaticLimitsCatalog,
    [string]   $StaticLimitsCatalogPath = (Join-Path (Split-Path -Parent $PSCommandPath) "AzureServiceLimits.psd1"),
    [int]      $MaxParallelRegions = 1
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ---------------------------------------------------------------------------
# Load static limits catalog (used to fill QuotaApproved for resource types
# that do not expose a live usage / quota API)
# ---------------------------------------------------------------------------
$StaticLimits = @{}
if (-not $SkipStaticLimitsCatalog) {
    if (Test-Path $StaticLimitsCatalogPath) {
        try {
            $loaded = Import-PowerShellDataFile -Path $StaticLimitsCatalogPath
            foreach ($key in $loaded.Keys) { $StaticLimits[$key.ToLowerInvariant()] = $loaded[$key] }
            Write-Host "Loaded $($StaticLimits.Count) static service-limit entries from $StaticLimitsCatalogPath"
        } catch {
            Write-Warning "Failed to load static limits catalog: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Static limits catalog not found at $StaticLimitsCatalogPath"
    }
}

# ---------------------------------------------------------------------------
# API versions (override here if a newer one is needed)
# ---------------------------------------------------------------------------
$ApiVersionDefaults = @{
    "Microsoft.Quota"            = "2025-09-01"
    "Microsoft.Resources"        = "2022-12-01"
    "Microsoft.Compute"          = "2024-07-01"
    "Microsoft.Network"          = "2024-05-01"
    "Microsoft.Storage"          = "2023-05-01"
    "Microsoft.Sql"              = "2023-08-01-preview"
    "Microsoft.Cache"            = "2024-11-01"
    "Microsoft.Web"              = "2023-12-01"
    "Microsoft.KeyVault"         = "2023-07-01"
    "Microsoft.ContainerInstance"= "2023-05-01"
    "Microsoft.ContainerRegistry"= "2023-11-01-preview"
    "Microsoft.ContainerService" = "2024-09-01"
    "Microsoft.Search"           = "2024-06-01-preview"
    "Microsoft.NetApp"           = "2024-09-01"
    "Microsoft.MachineLearningServices" = "2024-10-01"
    "Microsoft.RecoveryServices" = "2024-10-01"
    "Microsoft.Synapse"          = "2021-06-01"
    "Microsoft.HDInsight"        = "2024-08-01-preview"
    "Microsoft.Batch"            = "2024-07-01"
    "Microsoft.Devices"          = "2023-06-30"
    "Microsoft.SignalRService"   = "2024-03-01"
    "Microsoft.ServiceBus"       = "2024-01-01"
    "Microsoft.EventHub"         = "2024-01-01"
    "Microsoft.NotificationHubs" = "2023-09-01"
    "Microsoft.AVS"              = "2024-09-01"
    "Microsoft.DocumentDB"       = "2024-08-15"
    "Microsoft.DBforPostgreSQL"  = "2024-08-01"
    "Microsoft.DBforMySQL"       = "2023-12-30"
    "Microsoft.AppPlatform"      = "2024-05-01-preview"
    "Microsoft.Communication"    = "2023-06-01-preview"
    "Microsoft.OperationalInsights" = "2023-09-01"
    "Microsoft.Kusto"            = "2024-04-13"
    "Microsoft.StorageCache"     = "2024-07-01"
    "Microsoft.Purview"          = "2024-04-01-preview"
    "Microsoft.PowerBIDedicated" = "2021-01-01"
}

function Get-ApiVersionFor {
    param([string] $Provider)
    if ($ApiVersionDefaults.ContainsKey($Provider)) {
        return $ApiVersionDefaults[$Provider]
    }
    return "2024-01-01"
}

# ---------------------------------------------------------------------------
# Resource-scoped usages and quotas that ARM does not advertise as discrete
# resource types. Each entry says: enumerate parent resources via ARG, then
# GET {parentId}/{childPath}?api-version=...
# ---------------------------------------------------------------------------
$KnownResourceScopedUsages = @(
    @{
        Provider      = "Microsoft.ServiceBus"
        ParentType    = "microsoft.servicebus/namespaces"
        ChildPath     = "usages"
        Label         = "ServiceBus namespace usage"
    },
    @{
        Provider      = "Microsoft.EventHub"
        ParentType    = "microsoft.eventhub/namespaces"
        ChildPath     = "usages"
        Label         = "EventHub namespace usage"
    },
    @{
        Provider      = "Microsoft.NotificationHubs"
        ParentType    = "microsoft.notificationhubs/namespaces"
        ChildPath     = "usages"
        Label         = "NotificationHubs namespace usage"
    },
    @{
        Provider      = "Microsoft.Batch"
        ParentType    = "microsoft.batch/batchaccounts"
        ChildPath     = "quotas"
        Label         = "Batch account quotas"
    },
    @{
        Provider      = "Microsoft.RecoveryServices"
        ParentType    = "microsoft.recoveryservices/vaults"
        ChildPath     = "usages"
        Label         = "RecoveryServices vault usage"
    },
    @{
        Provider      = "Microsoft.MachineLearningServices"
        ParentType    = "microsoft.machinelearningservices/workspaces"
        ChildPath     = "quotas"
        Label         = "ML workspace quotas"
    },
    @{
        Provider      = "Microsoft.ContainerRegistry"
        ParentType    = "microsoft.containerregistry/registries"
        ChildPath     = "listUsages"
        Label         = "Container registry usage"
        Method        = "POST"
    },
    @{
        Provider      = "Microsoft.Devices"
        ParentType    = "microsoft.devices/iothubs"
        ChildPath     = "quotaMetrics"
        Label         = "IoT Hub quota metrics"
    },
    @{
        Provider      = "Microsoft.Sql"
        ParentType    = "microsoft.sql/servers"
        ChildPath     = "usages"
        Label         = "SQL logical server usages"
    },
    @{
        Provider      = "Microsoft.Synapse"
        ParentType    = "microsoft.synapse/workspaces"
        ChildPath     = "usages"
        Label         = "Synapse workspace usages"
    },
    @{
        Provider      = "Microsoft.DBforPostgreSQL"
        ParentType    = "microsoft.dbforpostgresql/flexibleservers"
        ChildPath     = "usages"
        Label         = "PostgreSQL flexible server usages"
    },
    @{
        Provider      = "Microsoft.DBforMySQL"
        ParentType    = "microsoft.dbformysql/flexibleservers"
        ChildPath     = "usages"
        Label         = "MySQL flexible server usages"
    },
    @{
        Provider      = "Microsoft.OperationalInsights"
        ParentType    = "microsoft.operationalinsights/workspaces"
        ChildPath     = "usages"
        Label         = "Log Analytics workspace usage"
    },
    @{
        Provider      = "Microsoft.KeyVault"
        ParentType    = "microsoft.keyvault/managedhsms"
        ChildPath     = "usages"
        Label         = "Managed HSM usage"
    },
    @{
        Provider      = "Microsoft.HDInsight"
        ParentType    = "microsoft.hdinsight/clusters"
        ChildPath     = "configurations"
        Label         = "HDInsight cluster configs"
    }
)

# ---------------------------------------------------------------------------
# Result accumulator
# ---------------------------------------------------------------------------
$Results = [System.Collections.Generic.List[object]]::new()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Invoke-ArmGet {
    param(
        [Parameter(Mandatory)] [string] $PathOrUri,
        [string] $Method = "GET",
        [string] $Body
    )

    $items = @()
    $next  = $PathOrUri
    $first = $true

    while (-not [string]::IsNullOrWhiteSpace($next)) {

        $params = @{ Method = if ($first) { $Method } else { "GET" } }
        if ($next -like "https://*") { $params.Uri  = $next }
        else                          { $params.Path = $next }
        if ($first -and $Method -eq "POST" -and $Body) { $params.Payload = $Body }

        $first    = $false
        $response = Invoke-AzRestMethod @params

        if ($response.StatusCode -ge 400) { return $items }
        if ([string]::IsNullOrWhiteSpace($response.Content)) { break }

        $json = $response.Content | ConvertFrom-Json -Depth 32 -ErrorAction SilentlyContinue
        if (-not $json) { break }

        if     ($json.value)    { $items += $json.value }
        elseif ($json.Quotas)   { $items += $json.Quotas }
        elseif ($json -is [System.Array]) { $items += $json }
        else                    { $items += $json }

        $next = $json.nextLink
    }

    return $items
}

function Test-NotEmpty {
    param($Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-DisplayName {
    param($Item)
    foreach ($candidate in @(
        $Item.properties.name.localizedValue,
        $Item.name.localizedValue,
        $Item.properties.displayName,
        $Item.properties.name.value,
        $Item.name.value,
        $Item.name)) {
        if (Test-NotEmpty $candidate) { return [string]$candidate }
    }
    return "n/a"
}

function Get-QuotaResourceName {
    param($Item)
    foreach ($candidate in @(
        $Item.properties.name.value,
        $Item.name.value,
        $Item.name)) {
        if (Test-NotEmpty $candidate) { return [string]$candidate }
    }
    return ""
}

function Get-LimitValue {
    param($Item)
    if ($null -ne $Item.properties.limit.value) { return [double]$Item.properties.limit.value }
    if ($null -ne $Item.properties.limit -and $Item.properties.limit -is [ValueType]) {
        return [double]$Item.properties.limit
    }
    if ($null -ne $Item.limit.value) { return [double]$Item.limit.value }
    if ($null -ne $Item.limit -and $Item.limit -is [ValueType]) { return [double]$Item.limit }
    if ($null -ne $Item.maxValue)    { return [double]$Item.maxValue }
    return $null
}

function Get-UsageValue {
    param($Item)
    if ($null -ne $Item.properties.usages.value)  { return [double]$Item.properties.usages.value }
    if ($null -ne $Item.properties.usage.value)   { return [double]$Item.properties.usage.value }
    if ($null -ne $Item.properties.currentValue)  { return [double]$Item.properties.currentValue }
    if ($null -ne $Item.currentValue)             { return [double]$Item.currentValue }
    if ($null -ne $Item.currentValueU64)          { return [double]$Item.currentValueU64 }
    return $null
}

function Get-Unit {
    param($Item)
    foreach ($candidate in @($Item.properties.unit, $Item.unit)) {
        if (Test-NotEmpty $candidate) { return [string]$candidate }
    }
    return ""
}

function Get-ProviderFromType {
    param([string] $Type)
    if ([string]::IsNullOrWhiteSpace($Type)) { return "" }
    return ($Type.Split("/")[0])
}

function Get-TypeWithoutProvider {
    param([string] $Type)
    if ([string]::IsNullOrWhiteSpace($Type)) { return "" }
    $parts = $Type.Split("/")
    if ($parts.Count -le 1) { return $Type }
    return ($parts[1..($parts.Count - 1)] -join "/")
}

function Add-Result {
    param(
        [string] $Subscription,
        [string] $SubscriptionId,
        [string] $Region,
        [string] $ResourceProvider,
        [string] $ResourceType,
        [string] $Sku,
        $QuotaApproved,
        $UsageCurrent,
        [string] $Unit,
        [string] $Source,
        [string] $CoverageNote
    )

    if (-not $IncludeZeroUsage) {
        $quotaEmpty = ($null -eq $QuotaApproved) -or ("$QuotaApproved" -eq "") -or ([double]"$QuotaApproved" -eq 0)
        $usageEmpty = ($null -eq $UsageCurrent ) -or ("$UsageCurrent"  -eq "") -or ([double]"$UsageCurrent"  -eq 0)
        if ($quotaEmpty -and $usageEmpty) { return }
    }

    $utilisation = $null
    if ($null -ne $QuotaApproved -and "$QuotaApproved" -ne "" -and
        $null -ne $UsageCurrent  -and "$UsageCurrent"  -ne "" -and
        [double]$QuotaApproved -gt 0) {
        $utilisation = [math]::Round(([double]$UsageCurrent / [double]$QuotaApproved) * 100, 2)
    }

    $Results.Add([PSCustomObject]@{
        Subscription       = $Subscription
        SubscriptionId     = $SubscriptionId
        Region             = $Region
        ResourceProvider   = $ResourceProvider
        ResourceType       = $ResourceType
        SKU                = $Sku
        QuotaApproved      = $QuotaApproved
        UsageCurrent       = $UsageCurrent
        UtilisationPercent = $utilisation
        Unit               = $Unit
        Source             = $Source
        CoverageNote       = $CoverageNote
    })
}

function Invoke-ResourceGraphAll {
    param(
        [Parameter(Mandatory)] [string]   $Query,
        [Parameter(Mandatory)] [string[]] $Subscriptions
    )

    $all       = @()
    $skipToken = $null

    do {
        $params = @{
            Query        = $Query
            Subscription = $Subscriptions
            First        = 1000
        }
        if ($skipToken) { $params.SkipToken = $skipToken }

        $page      = Search-AzGraph @params
        if ($page) { $all += $page }
        $skipToken = $page.SkipToken
    } while ($skipToken)

    return $all
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

$activeTenantId = (Get-AzContext).Tenant.Id

if ($SubscriptionIds -and $SubscriptionIds.Count -gt 0) {
    $subscriptions = foreach ($id in $SubscriptionIds) {
        try {
            Get-AzSubscription -SubscriptionId $id -TenantId $activeTenantId -WarningAction SilentlyContinue
        } catch {
            $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $id } | Select-Object -First 1
            if ($ctx) {
                [PSCustomObject]@{
                    Id     = $ctx.Subscription.Id
                    Name   = $ctx.Subscription.Name
                    State  = "Enabled"
                    TenantId = $ctx.Tenant.Id
                }
            } else {
                Write-Warning "Could not load subscription ${id}: $($_.Exception.Message)"
            }
        }
    }
} else {
    $subscriptions = Get-AzSubscription -TenantId $activeTenantId -WarningAction SilentlyContinue
}

if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    throw "No subscriptions found."
}

$subscriptionIdsToQuery = @($subscriptions.Id)
$subscriptionNameById   = @{}
foreach ($sub in $subscriptions) { $subscriptionNameById[$sub.Id] = $sub.Name }

# ---------------------------------------------------------------------------
# Layer 0: discover every RP that exposes "usages" or "quotas" resource types
# ---------------------------------------------------------------------------
function Get-UsageCapableProviders {
    param([string] $SubscriptionId)

    $resp = Invoke-AzRestMethod -Method GET `
        -Path "/subscriptions/$SubscriptionId/providers?api-version=2022-12-01&`$expand=resourceTypes/aliases"

    if ($resp.StatusCode -ge 400) { return @() }

    $json = $resp.Content | ConvertFrom-Json -Depth 64
    $capable = @()

    foreach ($p in $json.value) {
        if ($p.registrationState -ne "Registered") { continue }

        foreach ($rt in $p.resourceTypes) {
            $rtName = [string]$rt.resourceType
            if ($rtName -match '(^|/)usages$|(^|/)quotas$') {

                $apiVersion = if ($rt.defaultApiVersion) {
                    $rt.defaultApiVersion
                } elseif ($rt.apiVersions -and $rt.apiVersions.Count -gt 0) {
                    $rt.apiVersions[0]
                } else {
                    Get-ApiVersionFor -Provider $p.namespace
                }

                $locations = @()
                if ($rt.locations) { $locations = @($rt.locations) }

                $capable += [PSCustomObject]@{
                    Provider     = [string]$p.namespace
                    ResourceType = $rtName
                    ApiVersion   = $apiVersion
                    Locations    = $locations
                }
            }
        }
    }

    return $capable
}

# ---------------------------------------------------------------------------
# Per-subscription processing
# ---------------------------------------------------------------------------
foreach ($sub in $subscriptions) {

    Write-Host "==> Subscription: $($sub.Name)  [$($sub.Id)]" -ForegroundColor Cyan
    $setCtxArgs = @{ SubscriptionId = $sub.Id }
    if ($sub.TenantId) { $setCtxArgs.TenantId = $sub.TenantId }
    Set-AzContext @setCtxArgs -WarningAction SilentlyContinue | Out-Null

    if ($Regions -and $Regions.Count -gt 0) {
        $locationList = $Regions
    } else {
        $locationList = (Get-AzLocation | Where-Object { $_.Providers -contains "Microsoft.Compute" }).Location
    }

    # -----------------------------------------------------------------------
    # Layer 1: Microsoft.Quota (unified)
    # -----------------------------------------------------------------------
    Write-Host "    [1/6] Microsoft.Quota unified API"

    $quotaVersion = $ApiVersionDefaults["Microsoft.Quota"]
    $quotaProviderList = @(
        "Microsoft.Compute", "Microsoft.Network", "Microsoft.MachineLearningServices",
        "Microsoft.Storage", "Microsoft.StorageCache", "Microsoft.Sql",
        "Microsoft.Purview", "Microsoft.HDInsight", "Microsoft.NetApp",
        "Microsoft.AVS", "Microsoft.Web"
    )

    foreach ($region in $locationList) {
        foreach ($provider in $quotaProviderList) {

            $scope = "/subscriptions/$($sub.Id)/providers/$provider/locations/$region"
            try {
                $quotaItems = Invoke-ArmGet -PathOrUri "$scope/providers/Microsoft.Quota/quotas?api-version=$quotaVersion"
                $usageItems = Invoke-ArmGet -PathOrUri "$scope/providers/Microsoft.Quota/usages?api-version=$quotaVersion"

                $usageByName = @{}
                foreach ($u in $usageItems) {
                    $n = Get-QuotaResourceName -Item $u
                    if (Test-NotEmpty $n) { $usageByName[$n.ToLowerInvariant()] = $u }
                }

                foreach ($q in $quotaItems) {
                    $qName = Get-QuotaResourceName -Item $q
                    if (-not (Test-NotEmpty $qName)) { continue }

                    $uVal = $null
                    if ($usageByName.ContainsKey($qName.ToLowerInvariant())) {
                        $uVal = Get-UsageValue -Item $usageByName[$qName.ToLowerInvariant()]
                    }

                    Add-Result -Subscription $sub.Name -SubscriptionId $sub.Id `
                        -Region $region -ResourceProvider $provider `
                        -ResourceType "QuotaResource" `
                        -Sku (Get-DisplayName -Item $q) `
                        -QuotaApproved (Get-LimitValue -Item $q) `
                        -UsageCurrent  $uVal `
                        -Unit (Get-Unit -Item $q) `
                        -Source "Microsoft.Quota" `
                        -CoverageNote "Unified Microsoft.Quota API."
                }
            } catch { continue }
        }
    }

    # -----------------------------------------------------------------------
    # Layer 2 + 3 + 4: dynamic discovery of every RP that publishes usages /
    # quotas resource types
    # -----------------------------------------------------------------------
    Write-Host "    [2/6] Discovering provider-level usage endpoints"

    $capable = Get-UsageCapableProviders -SubscriptionId $sub.Id

    foreach ($cap in $capable) {

        $api      = $cap.ApiVersion
        $rtName   = $cap.ResourceType
        $provider = $cap.Provider

        # Subscription-scope endpoints: usages, quotas
        if ($rtName -eq "usages" -or $rtName -eq "quotas") {
            $path = "/subscriptions/$($sub.Id)/providers/$provider/$rtName`?api-version=$api"
            try {
                $items = Invoke-ArmGet -PathOrUri $path
                foreach ($item in $items) {
                    Add-Result -Subscription $sub.Name -SubscriptionId $sub.Id `
                        -Region "subscription-scope" -ResourceProvider $provider `
                        -ResourceType $rtName `
                        -Sku (Get-DisplayName -Item $item) `
                        -QuotaApproved (Get-LimitValue -Item $item) `
                        -UsageCurrent  (Get-UsageValue -Item $item) `
                        -Unit (Get-Unit -Item $item) `
                        -Source "$provider/$rtName" `
                        -CoverageNote "Subscription-scope $rtName from discovered RP."
                }
            } catch { continue }
        }

        # Regional endpoints: locations/usages, locations/quotas
        elseif ($rtName -eq "locations/usages" -or $rtName -eq "locations/quotas") {
            $childPath = $rtName.Split("/")[1]

            $regionsToTry = if ($cap.Locations.Count -gt 0) {
                $cap.Locations | ForEach-Object { $_.ToLower().Replace(" ", "") }
            } else { $locationList }

            foreach ($region in $regionsToTry) {
                if ($Regions -and $Regions.Count -gt 0 -and -not ($Regions -contains $region)) {
                    continue
                }

                $path = "/subscriptions/$($sub.Id)/providers/$provider/locations/$region/$childPath`?api-version=$api"
                try {
                    $items = Invoke-ArmGet -PathOrUri $path
                    foreach ($item in $items) {
                        Add-Result -Subscription $sub.Name -SubscriptionId $sub.Id `
                            -Region $region -ResourceProvider $provider `
                            -ResourceType $rtName `
                            -Sku (Get-DisplayName -Item $item) `
                            -QuotaApproved (Get-LimitValue -Item $item) `
                            -UsageCurrent  (Get-UsageValue -Item $item) `
                            -Unit (Get-Unit -Item $item) `
                            -Source "$provider/$rtName" `
                            -CoverageNote "Regional $rtName from discovered RP."
                    }
                } catch { continue }
            }
        }
    }

    # -----------------------------------------------------------------------
    # Layer 5: resource-scoped usages and quotas (namespace, vault, account...)
    # -----------------------------------------------------------------------
    if (-not $SkipResourceScopedUsages) {

        Write-Host "    [3/6] Resource-scoped usages (namespaces, vaults, accounts, workspaces)"

        foreach ($entry in $KnownResourceScopedUsages) {

            $parentQuery = "Resources | where subscriptionId == '$($sub.Id)' and type =~ '$($entry.ParentType)' | project id, name, location"
            try {
                $parents = Invoke-ResourceGraphAll -Query $parentQuery -Subscriptions @($sub.Id)
            } catch { continue }

            if (-not $parents) { continue }

            $api    = Get-ApiVersionFor -Provider $entry.Provider
            $method = if ($entry.Method) { $entry.Method } else { "GET" }

            foreach ($p in $parents) {
                $path = "$($p.id)/$($entry.ChildPath)?api-version=$api"
                try {
                    $items = Invoke-ArmGet -PathOrUri $path -Method $method
                    foreach ($item in $items) {
                        Add-Result -Subscription $sub.Name -SubscriptionId $sub.Id `
                            -Region $p.location -ResourceProvider $entry.Provider `
                            -ResourceType "$($entry.ParentType)/$($entry.ChildPath)" `
                            -Sku ("{0} :: {1}" -f $p.name, (Get-DisplayName -Item $item)) `
                            -QuotaApproved (Get-LimitValue -Item $item) `
                            -UsageCurrent  (Get-UsageValue -Item $item) `
                            -Unit (Get-Unit -Item $item) `
                            -Source "$($entry.Provider)/$($entry.ChildPath)" `
                            -CoverageNote $entry.Label
                    }
                } catch { continue }
            }
        }
    } else {
        Write-Host "    [3/6] Resource-scoped usages: skipped"
    }
}

# ---------------------------------------------------------------------------
# Layer 6: Azure Resource Graph inventory fallback
# ---------------------------------------------------------------------------
if (-not $SkipResourceGraphInventory) {

    Write-Host "==> [6/6] Azure Resource Graph inventory fallback" -ForegroundColor Cyan

    $resourceGraphQuery = @"
Resources
| extend skuName = tostring(sku.name)
| extend skuTier = tostring(sku.tier)
| extend skuSize = tostring(sku.size)
| extend region  = iff(isempty(location), 'global-or-unknown', tostring(location))
| extend sku     = case(
        isnotempty(skuName) and isnotempty(skuTier), strcat(skuName, ' / ', skuTier),
        isnotempty(skuName), skuName,
        isnotempty(skuTier), skuTier,
        isnotempty(skuSize), skuSize,
        'n/a')
| summarize UsageCurrent = count() by subscriptionId, region, type, sku
"@

    try {
        $argRows = Invoke-ResourceGraphAll -Query $resourceGraphQuery -Subscriptions $subscriptionIdsToQuery

        # Track which (subscriptionId, resourceType) pairs we saw so we can
        # later emit empty rows for catalog entries with zero deployed resources.
        $seenTypesBySub = @{}

        foreach ($row in $argRows) {
            $subName = if ($subscriptionNameById.ContainsKey($row.subscriptionId)) {
                $subscriptionNameById[$row.subscriptionId]
            } else { $row.subscriptionId }

            $typeLower = ([string]$row.type).ToLowerInvariant()
            if (-not $seenTypesBySub.ContainsKey($row.subscriptionId)) {
                $seenTypesBySub[$row.subscriptionId] = [System.Collections.Generic.HashSet[string]]::new()
            }
            [void]$seenTypesBySub[$row.subscriptionId].Add($typeLower)

            $staticLimit = $null
            $staticUnit  = "Count"
            $staticNote  = "Inventory fallback. Approved quota is not exposed by Azure for this row."
            $sourceTag   = "AzureResourceGraphInventory"

            if ($StaticLimits.ContainsKey($typeLower)) {
                $entry        = $StaticLimits[$typeLower]
                $staticLimit  = $entry.Limit
                if ($entry.Unit) { $staticUnit = [string]$entry.Unit }
                $scopeText    = if ($entry.Scope) { $entry.Scope } else { "subscription" }
                $noteSuffix   = if ($entry.Notes) { " " + $entry.Notes } else { "" }
                $staticNote   = "Inventory count joined with documented limit (scope=$scopeText, doc=$($entry.SourceDoc)).$noteSuffix"
                $sourceTag    = "AzureResourceGraphInventory+StaticLimit"
            }

            Add-Result -Subscription $subName -SubscriptionId $row.subscriptionId `
                -Region $row.region `
                -ResourceProvider (Get-ProviderFromType -Type $row.type) `
                -ResourceType    (Get-TypeWithoutProvider -Type $row.type) `
                -Sku             $row.sku `
                -QuotaApproved   $staticLimit `
                -UsageCurrent    $row.UsageCurrent `
                -Unit            $staticUnit `
                -Source          $sourceTag `
                -CoverageNote    $staticNote
        }

        # Emit documented-limit rows for catalog entries that have zero
        # deployed resources in each subscription, so the report covers the
        # FULL set of limited resource types -- not just deployed ones.
        if (-not $SkipStaticLimitsCatalog -and $IncludeZeroUsage) {
            foreach ($sub in $subscriptions) {
                $seen = if ($seenTypesBySub.ContainsKey($sub.Id)) {
                    $seenTypesBySub[$sub.Id]
                } else {
                    [System.Collections.Generic.HashSet[string]]::new()
                }

                foreach ($typeKey in $StaticLimits.Keys) {
                    if ($seen.Contains($typeKey)) { continue }
                    $entry      = $StaticLimits[$typeKey]
                    $scopeText  = if ($entry.Scope) { $entry.Scope } else { "subscription" }
                    $noteSuffix = if ($entry.Notes) { " " + $entry.Notes } else { "" }

                    Add-Result -Subscription $sub.Name -SubscriptionId $sub.Id `
                        -Region "n/a (no deployment)" `
                        -ResourceProvider (Get-ProviderFromType -Type $typeKey) `
                        -ResourceType    (Get-TypeWithoutProvider -Type $typeKey) `
                        -Sku             "documented-limit" `
                        -QuotaApproved   $entry.Limit `
                        -UsageCurrent    0 `
                        -Unit            ($entry.Unit | ForEach-Object { if ($_) { $_ } else { "Count" } }) `
                        -Source          "StaticServiceLimit" `
                        -CoverageNote    "Documented Azure limit (scope=$scopeText, doc=$($entry.SourceDoc)).$noteSuffix"
                }
            }
        }
    } catch {
        Write-Warning "Azure Resource Graph inventory collection failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
$sourceRank = {
    switch ($_.Source) {
        "Microsoft.Quota"             { 1 }
        "Microsoft.Compute/usages"    { 2 }
        "Microsoft.Compute/locations/usages" { 2 }
        "Microsoft.Network/usages"    { 3 }
        "Microsoft.Network/locations/usages" { 3 }
        "Microsoft.Storage/usages"    { 4 }
        "Microsoft.Sql/usages"        { 5 }
        "Microsoft.Sql/locations/usages" { 5 }
        "AzureResourceGraphInventory" { 99 }
        default                       { 50 }
    }
}

$final = $Results |
    Sort-Object Subscription, Region, ResourceProvider, ResourceType, SKU, @{Expression = $sourceRank}

$final | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$final |
    Select-Object Subscription, Region, ResourceProvider, ResourceType, SKU,
                  QuotaApproved, UsageCurrent, UtilisationPercent,
                  Unit, Source, CoverageNote |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Rows: $($final.Count)"
Write-Host "Export complete: $OutputPath"
