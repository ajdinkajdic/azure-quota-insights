#
# AzureServiceLimits.psd1
#
# Static catalog of documented Azure subscription / region limits, used to
# populate QuotaApproved for resource types that do not expose a live usage
# or quota API.
#
# Each entry:
#   <arm-resource-type-lowercase> = @{
#       Limit          = <int|long>          # documented default soft limit
#       Scope          = "subscription"      # or "subscription-region" or "resource-group"
#       Unit           = "Count" / "Cores" / "GiB" etc.
#       SourceDoc      = "<MS Learn anchor>"
#       Notes          = "<optional caveat>"
#   }
#
# Verified against:
#   https://learn.microsoft.com/azure/azure-resource-manager/management/azure-subscription-service-limits
#
# This catalog only contains limits NOT exposed by live APIs.
# Live API coverage already exists for:
#   Microsoft.Compute, Microsoft.Network, Microsoft.Storage,
#   Microsoft.Sql, Microsoft.Cache, Microsoft.Web (partial),
#   Microsoft.KeyVault (partial via Microsoft.Quota),
#   Microsoft.MachineLearningServices, Microsoft.HDInsight,
#   Microsoft.NetApp, Microsoft.AVS, Microsoft.ContainerRegistry,
#   Microsoft.ContainerInstance, Microsoft.Search.
#
# When live API and static catalog disagree, live API wins.
#
@{

    # ------------------------- General / governance -------------------------
    "microsoft.resources/subscriptions/resourcegroups" = @{
        Limit = 980; Scope = "subscription"; Unit = "Count"
        SourceDoc = "azure-subscription-limits"
        Notes = "Resource groups per subscription."
    }
    "microsoft.authorization/roleassignments" = @{
        Limit = 4000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "rbac-limits"
        Notes = "Role assignments per subscription. Hard limit 8000."
    }
    "microsoft.authorization/roledefinitions" = @{
        Limit = 5000; Scope = "tenant"; Unit = "Count"
        SourceDoc = "rbac-limits"
        Notes = "Custom role definitions per tenant."
    }
    "microsoft.authorization/policydefinitions" = @{
        Limit = 500; Scope = "subscription"; Unit = "Count"
        SourceDoc = "azure-policy-limits"
    }
    "microsoft.authorization/policyassignments" = @{
        Limit = 200; Scope = "scope"; Unit = "Count"
        SourceDoc = "azure-policy-limits"
    }
    "microsoft.management/managementgroups" = @{
        Limit = 10000; Scope = "tenant"; Unit = "Count"
        SourceDoc = "management-group-limits"
    }
    "microsoft.resources/deployments" = @{
        Limit = 800; Scope = "resource-group"; Unit = "Count"
        SourceDoc = "resource-group-limits"
        Notes = "Deployments per resource group in deployment history."
    }

    # ------------------------- AKS / Container Apps -------------------------
    "microsoft.containerservice/managedclusters" = @{
        Limit = 5000; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "aks-limits"
        Notes = "Maximum clusters per subscription per region."
    }
    "microsoft.containerservice/fleets" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "aks-limits"
    }
    "microsoft.app/managedenvironments" = @{
        Limit = 15; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "container-apps-limits"
    }
    "microsoft.app/containerapps" = @{
        Limit = 1000; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "container-apps-limits"
    }
    "microsoft.app/jobs" = @{
        Limit = 100; Scope = "managed-environment"; Unit = "Count"
        SourceDoc = "container-apps-limits"
    }
    "microsoft.containerinstance/containergroups" = @{
        Limit = 100; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "container-instances-limits"
    }

    # ------------------------- Cosmos / data --------------------------------
    "microsoft.documentdb/databaseaccounts" = @{
        Limit = 50; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "cosmos-db-limits"
        Notes = "Database accounts per subscription per region."
    }
    "microsoft.documentdb/mongoclusters" = @{
        Limit = 40; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "cosmos-db-limits"
    }

    # ------------------------- App Service / Functions ----------------------
    "microsoft.web/serverfarms" = @{
        Limit = 100; Scope = "resource-group"; Unit = "Count"
        SourceDoc = "app-service-limits"
        Notes = "App Service plans per resource group."
    }
    "microsoft.web/sites" = @{
        Limit = 500; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "app-service-limits"
        Notes = "Apps per region per subscription (varies by SKU)."
    }
    "microsoft.web/staticsites" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "app-service-limits"
    }
    "microsoft.web/hostingenvironments" = @{
        Limit = 5; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "app-service-limits"
        Notes = "App Service Environments (v3)."
    }

    # ------------------------- Messaging ------------------------------------
    "microsoft.servicebus/namespaces" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "service-bus-limits"
    }
    "microsoft.eventhub/namespaces" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "event-hubs-limits"
    }
    "microsoft.eventhub/clusters" = @{
        Limit = 5; Scope = "subscription"; Unit = "Count"
        SourceDoc = "event-hubs-limits"
    }
    "microsoft.notificationhubs/namespaces" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "notification-hubs-limits"
    }
    "microsoft.eventgrid/topics" = @{
        Limit = 100; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "event-grid-limits"
    }
    "microsoft.eventgrid/systemtopics" = @{
        Limit = 100; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "event-grid-limits"
    }
    "microsoft.eventgrid/domains" = @{
        Limit = 100; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "event-grid-limits"
    }
    "microsoft.eventgrid/namespaces" = @{
        Limit = 5; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "event-grid-namespace-limits"
    }

    # ------------------------- Realtime -------------------------------------
    "microsoft.signalrservice/signalr" = @{
        Limit = 30; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "signalr-service-limits"
    }
    "microsoft.signalrservice/webpubsub" = @{
        Limit = 30; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "web-pubsub-limits"
    }

    # ------------------------- Integration ----------------------------------
    "microsoft.logic/workflows" = @{
        Limit = 1000; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "logic-apps-limits"
    }
    "microsoft.logic/integrationaccounts" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "logic-apps-limits"
    }
    "microsoft.apimanagement/service" = @{
        Limit = 20; Scope = "subscription"; Unit = "Count"
        SourceDoc = "api-management-limits"
    }
    "microsoft.datafactory/factories" = @{
        Limit = 800; Scope = "subscription"; Unit = "Count"
        SourceDoc = "data-factory-limits"
    }

    # ------------------------- AI / Cognitive / Search ----------------------
    "microsoft.cognitiveservices/accounts" = @{
        Limit = 200; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "cognitive-services-limits"
    }
    "microsoft.search/searchservices" = @{
        Limit = 12; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "search-limits"
        Notes = "Free + Basic tier default per subscription per region."
    }

    # ------------------------- Key management -------------------------------
    "microsoft.keyvault/vaults" = @{
        Limit = 500; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "key-vault-limits"
    }
    "microsoft.keyvault/managedhsms" = @{
        Limit = 5; Scope = "subscription"; Unit = "Count"
        SourceDoc = "key-vault-limits"
    }
    "microsoft.appconfiguration/configurationstores" = @{
        Limit = 200; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "app-configuration-limits"
    }

    # ------------------------- IoT / Edge -----------------------------------
    "microsoft.devices/iothubs" = @{
        Limit = 50; Scope = "subscription"; Unit = "Count"
        SourceDoc = "iot-hub-limits"
    }
    "microsoft.devices/provisioningservices" = @{
        Limit = 10; Scope = "subscription"; Unit = "Count"
        SourceDoc = "iot-dps-limits"
    }
    "microsoft.iotcentral/iotapps" = @{
        Limit = 10; Scope = "subscription"; Unit = "Count"
        SourceDoc = "iot-central-limits"
    }
    "microsoft.digitaltwins/digitaltwinsinstances" = @{
        Limit = 10; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "digital-twins-limits"
    }
    "microsoft.databoxedge/databoxedgedevices" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "databox-edge-limits"
    }

    # ------------------------- Analytics ------------------------------------
    "microsoft.synapse/workspaces" = @{
        Limit = 20; Scope = "subscription"; Unit = "Count"
        SourceDoc = "synapse-limits"
    }
    "microsoft.kusto/clusters" = @{
        Limit = 20; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "data-explorer-limits"
    }
    "microsoft.purview/accounts" = @{
        Limit = 1; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "purview-limits"
        Notes = "Default Purview account quota per subscription per region."
    }
    "microsoft.databricks/workspaces" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "databricks-limits"
    }
    "microsoft.streamanalytics/streamingjobs" = @{
        Limit = 1500; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "stream-analytics-limits"
    }

    # ------------------------- Backup / DR ----------------------------------
    "microsoft.recoveryservices/vaults" = @{
        Limit = 500; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "backup-limits"
    }
    "microsoft.dataprotection/backupvaults" = @{
        Limit = 500; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "backup-limits"
    }

    # ------------------------- Networking (no live API per type) ------------
    "microsoft.network/dnszones" = @{
        Limit = 250; Scope = "subscription"; Unit = "Count"
        SourceDoc = "dns-limits"
    }
    "microsoft.network/privatednszones" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "dns-limits"
    }
    "microsoft.network/trafficmanagerprofiles" = @{
        Limit = 200; Scope = "subscription"; Unit = "Count"
        SourceDoc = "traffic-manager-limits"
    }
    "microsoft.network/frontdoors" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "front-door-limits"
    }
    "microsoft.cdn/profiles" = @{
        Limit = 25; Scope = "subscription"; Unit = "Count"
        SourceDoc = "cdn-limits"
    }

    # ------------------------- Container Registry (per-tier counts) ---------
    "microsoft.containerregistry/registries" = @{
        Limit = 500; Scope = "subscription"; Unit = "Count"
        SourceDoc = "container-registry-limits"
    }

    # ------------------------- Machine Learning -----------------------------
    "microsoft.machinelearningservices/workspaces" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "machine-learning-limits"
    }

    # ------------------------- Maps / monitoring ----------------------------
    "microsoft.maps/accounts" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "maps-limits"
    }
    "microsoft.insights/components" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "app-insights-limits"
    }
    "microsoft.operationalinsights/workspaces" = @{
        Limit = 100; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "monitor-limits"
    }
    "microsoft.automation/automationaccounts" = @{
        Limit = 100; Scope = "subscription"; Unit = "Count"
        SourceDoc = "automation-limits"
    }
    "microsoft.grafana/grafana" = @{
        Limit = 20; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "managed-grafana-limits"
    }

    # ------------------------- Identity -------------------------------------
    "microsoft.aad/domainservices" = @{
        Limit = 1; Scope = "tenant"; Unit = "Count"
        SourceDoc = "azure-ad-domain-services-limits"
    }
    "microsoft.managedidentity/userassignedidentities" = @{
        Limit = 1000; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "managed-identity-limits"
    }

    # ------------------------- VDI / Lab ------------------------------------
    "microsoft.desktopvirtualization/hostpools" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "azure-virtual-desktop-limits"
    }
    "microsoft.desktopvirtualization/workspaces" = @{
        Limit = 1000; Scope = "subscription"; Unit = "Count"
        SourceDoc = "azure-virtual-desktop-limits"
    }
    "microsoft.labservices/labplans" = @{
        Limit = 5; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "lab-services-limits"
    }

    # ------------------------- Healthcare -----------------------------------
    "microsoft.healthcareapis/workspaces" = @{
        Limit = 10; Scope = "subscription"; Unit = "Count"
        SourceDoc = "health-data-services-limits"
    }

    # ------------------------- Batch ----------------------------------------
    "microsoft.batch/batchaccounts" = @{
        Limit = 3; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "batch-limits"
    }

    # ------------------------- Cloud Services -------------------------------
    "microsoft.cloudshell/consoles" = @{
        Limit = 1; Scope = "user"; Unit = "Count"
        SourceDoc = "cloud-shell-limits"
    }

    # ------------------------- Load Testing ---------------------------------
    "microsoft.loadtestservice/loadtests" = @{
        Limit = 5; Scope = "subscription-region"; Unit = "Count"
        SourceDoc = "load-testing-limits"
    }
}
