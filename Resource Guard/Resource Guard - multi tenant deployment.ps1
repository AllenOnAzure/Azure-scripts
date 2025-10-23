# Resource Guard - multi tenant deployment # 
# Synopsis is explained at the bottom of the script

# Deploy Resource Guard across 2 tenants:

## Step 1 - Variables
$sourceTenantId = "<source-tenant-id>"
$targetTenantId = "<target-tenant-id>"
$sourceSubId = "<source-subscription-id>"
$targetSubId = "<target-subscription-id>"
$rgName = "rg-resourceguard-prod"
$location = "uksouth"
$resourceGuardName = "rguard-backup-prod"


## Step 2 - Connect to target tenant and create Resource Group (Resoure Guard)#
Connect-AzAccount -Tenant $targetTenantId
Set-AzContext -Subscription $targetSubId
New-AzResourceGroup -Name $rgName -Location $location


## Step 3 - Create Resource Guard in target tenant
$resourceGuard = New-AzDataProtectionResourceGuard `
    -SubscriptionId $targetSubId `
    -ResourceGroupName $rgName `
    -Name $resourceGuardName `
    -Location $location

## Step 4 - Select operations to protect:
$criticalOperations = $resourceGuard.ResourceGuardOperation.VaultCriticalOperation
$operationsToBeExcluded = $criticalOperations | Where-Object { 
    $_ -match "backupSecurityPIN/action" -or 
    $_ -match "backupInstances/delete" 
}

## Step 5 - Update Resource Guard with protected operations:
Update-AzDataProtectionResourceGuard `
    -SubscriptionId $targetSubId `
    -ResourceGroupName $rgName `
    -Name $resourceGuardName `
    -ProtectedOperation ($criticalOperations | Where-Object { $_ -notin $operationsToBeExcluded })


## Step 6 - Create service principal in target tenant for cross-tenant access:
$sp = New-AzADServicePrincipal -DisplayName "ResourceGuard-CrossTenant"
$spSecret = New-AzADServicePrincipalCredential -ObjectId $sp.Id
$resourceGuardId = $resourceGuard.Id

# Step 7 - Assign RBAC role to service principal
New-AzRoleAssignment `
    -ApplicationId $sp.ApplicationId `
    -RoleDefinitionName "Resource Guard Operator" `
    -Scope $resourceGuardId

# Step 8 - Switch to source tenant and associate Resource Guard
Connect-AzAccount -Tenant $sourceTenantId
Set-AzContext -Subscription $sourceSubId

# Create service principal credentials:
$securePassword = ConvertTo-SecureString $spSecret.SecretText -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($sp.ApplicationId, $securePassword)

# Connect using service principal:
Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $targetTenantId

# Associate Resource Guard with backup vault in source tenant:
$vault = Get-AzDataProtectionBackupVault -SubscriptionId $sourceSubId -ResourceGroupName "<source-rg-name>"

Update-AzDataProtectionBackupVault `
    -SubscriptionId $sourceSubId `
    -ResourceGroupName $vault.ResourceGroupName `
    -VaultName $vault.Name `
    -ResourceGuardId $resourceGuardId

<# Synopsis:
Steps Explained:
Step 1 – Define Variables:
Sets tenant IDs, subscription IDs, resource group name, location, and Resource Guard name.
These variables are used throughout the script for consistency.

Step 2 – Connect to Target Tenant:
Authenticates to the target tenant using Connect-AzAccount.
Switches context to the target subscription with Set-AzContext.
Creates a Resource Group in the target tenant where Resource Guard will reside.

Step 3 – Create Resource Guard:
Deploys a Resource Guard in the target tenant using New-AzDataProtectionResourceGuard.
Stores the Resource Guard object in $resourceGuard.

Step 4 – Identify Critical Operations:
Retrieves all critical operations that Resource Guard can protect.
Filters out operations that should NOT be protected (e.g., backupSecurityPIN/action and backupInstances/delete).

Step 5 – Update Resource Guard:
Updates Resource Guard to protect all critical operations except the excluded ones.

Step 6 – Create Service Principal:
Creates a service principal in the target tenant for cross-tenant access.
Generates a secret credential for the service principal.
Captures the Resource Guard ID for later use.

Step 7 – Assign RBAC Role:
Assigns the Resource Guard Operator role to the service principal.
Scope is limited to the Resource Guard resource.

Step 8 – Switch to Source Tenant:
Connects to the source tenant and sets context to its subscription.
Converts the service principal secret into a secure credential.
Authenticates to the target tenant using the service principal (cross-tenant login).
Retrieves the backup vault in the source tenant.
Associates the Resource Guard from the target tenant with the backup vault in the source tenant.

Key Outcome:
Resource Guard in target tenant protects critical operations for backup vault in source tenant.
Cross-tenant access is enabled via service principal with RBAC permissions.

#>	
