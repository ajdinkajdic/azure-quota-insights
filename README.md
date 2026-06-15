# Azure Quota & Usage – Composite Reporter

A read-only reporting toolkit that pulls **approved quota** and **current usage**
for every Azure resource type that exposes (or has documented) limits, across
every subscription and every region in a tenant.

Two files make up the toolkit:

| File | Role |
|---|---|
| `Get-AzureQuotaUsageAll.ps1` | Main script. Walks 6 coverage layers and writes a single CSV. |
| `AzureServiceLimits.psd1`    | Static catalog of documented Azure limits used to fill `QuotaApproved` for resource types that have no live API. |

---

## 1. Prerequisites

- **PowerShell 7.2+**
- **Az modules** (already installed on this machine, verified versions):
  - `Az.Accounts` 5.3.4
  - `Az.Resources` 9.0.3
  - `Az.ResourceGraph` 1.0.0
- An Azure identity with **Reader** on every subscription you want to scan
  (the script never writes anything)

Install if missing:

```powershell
Install-Module Az.Accounts, Az.Resources, Az.ResourceGraph -Scope CurrentUser
```

---

## 2. Step-by-step run guide

### Step 1 — Sign in once per tenant

```powershell
Connect-AzAccount -TenantId <YourTenantId>
```

If your tenant requires MFA and a browser pop-up is blocked, use device code:

```powershell
Connect-AzAccount -TenantId <YourTenantId> -UseDeviceAuthentication
```

The Az context is persisted to disk (`~/.Azure`), so subsequent PowerShell
sessions see the same login until the token expires.

### Step 2 — Smoke test (1 subscription, 1 region, live APIs only)

Quick sanity check, ~1–2 minutes:

```powershell
cd ~/Documents
./Get-AzureQuotaUsageAll.ps1 `
    -SubscriptionIds '<SubId>' `
    -Regions 'westeurope' `
    -OutputPath './AzureQuotaUsage_Smoke.csv' `
    -SkipResourceScopedUsages `
    -SkipResourceGraphInventory
```

Expected: a few hundred to ~1000 rows, dominated by `Microsoft.Quota` and
`<provider>/locations/usages` source tags.

### Step 3 — Single region, full coverage (validates all 6 layers)

~5–10 minutes:

```powershell
./Get-AzureQuotaUsageAll.ps1 `
    -SubscriptionIds '<SubId>' `
    -Regions 'westeurope' `
    -OutputPath './AzureQuotaUsage_Region.csv'
```

Now you also see `AzureResourceGraphInventory+StaticLimit` and resource-scoped
rows (`<provider>/usages`, `<provider>/quotas`).

### Step 4 — Production run (all subscriptions, all regions)

~30–60 minutes for a 5–10 subscription tenant. Run from a stable terminal /
tmux / detached PowerShell job:

```powershell
./Get-AzureQuotaUsageAll.ps1 `
    -OutputPath './AzureQuotaUsage_Full.csv' `
    -IncludeZeroUsage
```

`-IncludeZeroUsage` also emits one row per **catalog entry that has zero
deployed resources** in each subscription, giving you a complete "headroom"
view (not just things you've already provisioned).

### Step 5 — Inspect the output

The CSV columns are:

| Column | Meaning |
|---|---|
| `Subscription`, `SubscriptionId` | Where the row was collected. |
| `Region` | Region or `subscription-scope` / `n/a (no deployment)`. |
| `ResourceProvider`, `ResourceType` | ARM identification of the resource. |
| `SKU` | SKU/family or quota name (e.g. `standardDSv5Family`). |
| `QuotaApproved` | Approved limit (live API or documented). |
| `UsageCurrent` | Current consumption / deployed count. |
| `UtilisationPercent` | `UsageCurrent / QuotaApproved * 100`. |
| `Unit` | `Count`, `Cores`, `GiB`, etc. |
| `Source` | Which layer produced this row (see §3). |
| `CoverageNote` | Human-readable note about scope / API origin. |

Sort by `UtilisationPercent` descending to find what's about to run out of
quota.

---

## 3. The six coverage layers

| # | Source tag examples | What it queries | Limit | Usage |
|---|---|---|---|---|
| 1 | `Microsoft.Quota` | Unified Microsoft.Quota API for 11 hardcoded providers (Compute, Network, ML, Storage, StorageCache, Sql, Purview, HDInsight, NetApp, AVS, Web). | ✅ live | ✅ live |
| 2 | `<RP>/locations/usages` | Every RP whose ARM provider metadata advertises a `locations/usages` or `locations/quotas` resource type. **Discovered at runtime** — no hardcoded list. | ✅ live | ✅ live |
| 3 | `<RP>/usages`, `<RP>/quotas` | Same discovery but at subscription scope (e.g. Microsoft.Storage, Microsoft.Devices, Microsoft.NotificationHubs). | ✅ live | ✅ live |
| 4 | `<RP>/<child>` | Per-namespace / per-vault / per-workspace endpoints that ARM does *not* publish as standalone resource types. Curated map (15 entries) covering Service Bus, Event Hubs, Batch, Recovery Services, ML, Container Registry, IoT Hub, SQL servers, Synapse, Postgres / MySQL flexible servers, Log Analytics, Managed HSM, HDInsight. | ✅ live | ✅ live |
| 5 | `AzureResourceGraphInventory+StaticLimit` | ARG inventory count joined against `AzureServiceLimits.psd1`. | 📘 doc | ✅ live count |
| 6 | `AzureResourceGraphInventory` | ARG inventory count only (catalog has no entry for this type). | ❌ | ✅ live count |
| 6b | `StaticServiceLimit` (only with `-IncludeZeroUsage`) | Pure documented limits for catalog entries with zero deployed resources. | 📘 doc | 0 |

Layer 2 is the magic — when a new Azure RP ships a `locations/usages` endpoint
tomorrow, this script picks it up automatically with no code change. Verified
on real tenant: discovered 18 RPs in `westeurope` without any hand-curated list,
including ones not even mentioned in the script (`Microsoft.Fabric`,
`Microsoft.DataLakeAnalytics`, `Microsoft.Automation`, etc.).

---

## 4. The script (`Get-AzureQuotaUsageAll.ps1`) – walkthrough

```
param block               -- subscription / region / output / skip switches
load static catalog       -- Import-PowerShellDataFile AzureServiceLimits.psd1
Helpers
  Invoke-ArmGet           -- generic pageable ARM GET/POST, swallows 4xx
  Get-LimitValue          -- normalises {limit, properties.limit, ...}
  Get-UsageValue          -- normalises {currentValue, properties.usages.value, ...}
  Get-DisplayName         -- normalises {properties.name.localizedValue, ...}
  Get-Unit, Get-QuotaResourceName, Get-ProviderFromType, Get-TypeWithoutProvider
  Add-Result              -- normalised row builder; computes UtilisationPercent
  Invoke-ResourceGraphAll -- pageable Search-AzGraph (handles SkipToken)

Bootstrap
  Get-AzContext, build subscriptions list (-SubscriptionIds or all in tenant)

For each subscription:
  Layer 1  Microsoft.Quota               (11 hardcoded providers)
  Layer 2+3  Get-UsageCapableProviders   (dynamic discovery)
              -> for each "locations/usages|quotas"     call per region
              -> for each subscription-level "usages|quotas" call once
  Layer 4  KnownResourceScopedUsages     (parent enumeration via ARG, then GET)

Cross-subscription:
  Layer 5  ARG inventory query
            -> join against $StaticLimits      (-> +StaticLimit rows)
            -> emit StaticServiceLimit for catalog entries with no deployment
               (only with -IncludeZeroUsage)

Export-Csv, Format-Table summary
```

Design choices worth knowing:

- **`Invoke-ArmGet` returns `@()` on any 4xx instead of throwing** — most RPs
  don't support every region/scope; silent skip keeps the report flowing.
- **API versions are pinned per RP** in `$ApiVersionDefaults`. Override any of
  them at the top of the file. The discovery layer uses each RP's own
  `defaultApiVersion` returned from ARM provider metadata, so it stays current
  automatically.
- **ARG inventory is queried once across all subscriptions** in one call rather
  than per-sub; this is dramatically faster than fanning out REST calls.
- **`-IncludeZeroUsage`** is required to see catalog entries with no
  deployment. Without it, the report is restricted to rows where either
  `QuotaApproved` or `UsageCurrent` is non-zero, which keeps the output
  practical for utilisation triage.
- **`Set-AzContext` is passed `TenantId`** explicitly so multi-tenant accounts
  don't trip on cached but expired tokens for a different tenant.

---

## 5. The catalog (`AzureServiceLimits.psd1`) – walkthrough

A flat PowerShell data file mapping **lowercase ARM resource types** to
documented limit metadata:

```powershell
"microsoft.containerservice/managedclusters" = @{
    Limit     = 5000
    Scope     = "subscription-region"
    Unit      = "Count"
    SourceDoc = "aks-limits"
    Notes     = "Maximum clusters per subscription per region."
}
```

Fields:

| Field | Purpose |
|---|---|
| `Limit` | The documented soft limit. Use the most representative default tier. |
| `Scope` | `subscription`, `subscription-region`, `resource-group`, `tenant`, or `scope`. Informational only — affects `CoverageNote`. |
| `Unit` | `Count`, `Cores`, `GiB`, etc. Free text. |
| `SourceDoc` | Anchor inside [Azure subscription and service limits](https://learn.microsoft.com/azure/azure-resource-manager/management/azure-subscription-service-limits). |
| `Notes` | Optional caveat (e.g. *"Hard limit 8000"*). |

The catalog currently ships with **71 verified entries** covering AKS,
Container Apps, Cosmos, App Service, Service Bus, Event Hubs, Event Grid,
SignalR, Web PubSub, Logic Apps, APIM, Cognitive Services, Search, Key Vault,
App Configuration, IoT, Synapse, Kusto, Purview, Databricks, Recovery Services,
DNS, Front Door, CDN, ML, Maps, App Insights, Log Analytics, Automation,
Managed Grafana, AVD, Lab Services, Healthcare APIs, Batch, Load Testing, plus
governance (RGs, RBAC, policy, management groups).

### When to extend the catalog

Run Stage 3 with `-IncludeZeroUsage`, then run:

```powershell
Import-Csv AzureQuotaUsage_Full.csv |
    Where-Object { $_.Source -eq 'AzureResourceGraphInventory' } |
    Select-Object -Unique ResourceProvider, ResourceType |
    Sort-Object ResourceProvider, ResourceType
```

Anything in that list is a deployed type whose limit you do **not** yet have.
Add an entry to `AzureServiceLimits.psd1` (no script changes required), re-run.

### Catalog rules of thumb

- **Skip types already covered by Layer 1–4.** Live API wins anyway and you
  avoid duplicate rows. (Compute, Network, Storage, Sql, ML, KeyVault and
  others are intentionally not in the catalog.)
- **Pick the default tier limit** when limits differ by SKU (e.g. App Service
  Plans per RG is 100 regardless of SKU; Cosmos accounts is 50 per sub per
  region default).
- **Lowercase keys.** The lookup is case-insensitive but the import is verbatim.

---

## 6. Operations cheat sheet

| Goal | How |
|---|---|
| One subscription | `-SubscriptionIds 'xxx'` |
| Several subs | `-SubscriptionIds 'a','b','c'` |
| Specific regions | `-Regions 'westeurope','switzerlandnorth'` |
| Skip per-namespace walk (faster) | `-SkipResourceScopedUsages` |
| Skip ARG inventory + catalog | `-SkipResourceGraphInventory` |
| Show full catalog including zero-deployment entries | `-IncludeZeroUsage` |
| Use a different catalog file | `-StaticLimitsCatalogPath /path/to/other.psd1` |
| Override an RP's API version | edit `$ApiVersionDefaults` at the top of the script |
| Add a new resource-scoped usage endpoint | add an entry to `$KnownResourceScopedUsages` array |

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No subscriptions found.` | The Az context lost auth. Re-run `Connect-AzAccount -TenantId <id>`. The script now passes `TenantId` to `Set-AzContext` to avoid empty-tenant errors. |
| `WARNING: Unable to acquire token for tenant ...` | One of your tenants needs MFA re-auth. Safe to ignore for tenants you don't care about — script uses only the active tenant. |
| ARG inventory empty | `Az.ResourceGraph` not installed, or identity has no Reader on the subscription. |
| Many `<provider>/locations/usages` rows missing | That RP isn't registered in your subscription. Register with `Register-AzResourceProvider -ProviderNamespace <RP>`. |
| Rows missing `QuotaApproved` for a deployed type | The type has no live API and no catalog entry. Add one to `AzureServiceLimits.psd1`. |

---