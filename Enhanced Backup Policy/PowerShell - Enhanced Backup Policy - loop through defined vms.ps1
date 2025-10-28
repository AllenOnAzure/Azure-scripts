# PowerShell - Enhanced Backup Policy for Azure VMs v3

# Step 0: Define your specific VMs and configuration:
$VMNames = @("Linux-VM01", "Linux-VM02", "Linux-VM03", "Linux-VM04")
$SourceResourceGroupName = "ALLENS-LINUX-VMS"
$BackupResourceGroupName = "vm-backups"
$RSVname = "vm-backups"
$RSVpolicyName = "Enhanced-Hourly-Backup-Policy"

Write-Host "Starting Azure Backup Configuration..." -ForegroundColor Cyan
Write-Host "Source Resource Group: $SourceResourceGroupName" -ForegroundColor Yellow
Write-Host "Backup Resource Group: $BackupResourceGroupName" -ForegroundColor Yellow
Write-Host "Vault Name: $RSVname" -ForegroundColor Yellow
Write-Host "VMs to protect: $($VMNames -join ', ')" -ForegroundColor Yellow

# Step 1: Check basic connectivity and permissions
Write-Host "`nStep 1: Checking Azure connectivity and permissions..." -ForegroundColor Cyan

try {
    $context = Get-AzContext -ErrorAction Stop
    Write-Host "Connected to Azure Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Host "Not connected to Azure. Please run: Connect-AzAccount" -ForegroundColor Red
    exit
}

# Step 2: Check source resource group access
try {
    $rg = Get-AzResourceGroup -Name $SourceResourceGroupName -ErrorAction Stop
    Write-Host "Source Resource Group found: $($rg.ResourceGroupName)" -ForegroundColor Green
}
catch {
    Write-Host "Cannot access Source Resource Group '$SourceResourceGroupName'" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Please check:" -ForegroundColor Yellow
    Write-Host "  1. Resource group name is correct" -ForegroundColor Yellow
    Write-Host "  2. You have 'Reader' role on the resource group" -ForegroundColor Yellow
    exit
}

# Step 3: Create or verify backup resource group:
Write-Host "`nStep 2: Creating/verifying backup resource group..." -ForegroundColor Cyan
try {
    $backupRG = Get-AzResourceGroup -Name $BackupResourceGroupName -ErrorAction SilentlyContinue
    
    if (-not $backupRG) {
        Write-Host "Backup resource group '$BackupResourceGroupName' not found. Creating new one..." -ForegroundColor Yellow
        
        # Choose a location for the backup resource group (using the same location as source RG)
        $location = $rg.Location
        New-AzResourceGroup -Name $BackupResourceGroupName -Location $location -Force
        Write-Host "Successfully created backup resource group: $BackupResourceGroupName in $location" -ForegroundColor Green
    }
    else {
        Write-Host "Backup resource group already exists: $BackupResourceGroupName" -ForegroundColor Green
    }
}
catch {
    Write-Host "Error creating/accessing backup resource group: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Step 4: Create or verify Recovery Services Vault:
Write-Host "`nStep 3: Creating/verifying Recovery Services Vault..." -ForegroundColor Cyan
try {
    $vault = Get-AzRecoveryServicesVault -ResourceGroupName $BackupResourceGroupName -Name $RSVname -ErrorAction SilentlyContinue
    
    if (-not $vault) {
        Write-Host "Recovery Services Vault '$RSVname' not found. Creating new one..." -ForegroundColor Yellow
        
        # Use the same location as the backup resource group
        $backupRG = Get-AzResourceGroup -Name $BackupResourceGroupName
        $location = $backupRG.Location
        
        $vault = New-AzRecoveryServicesVault -Name $RSVname -ResourceGroupName $BackupResourceGroupName -Location $location
        Write-Host "Successfully created Recovery Services Vault: $($vault.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "Recovery Services Vault already exists: $($vault.Name)" -ForegroundColor Green
    }
    
    # Set vault context
    Set-AzRecoveryServicesVaultContext -Vault $vault -ErrorAction Stop
    Write-Host "Vault context set successfully" -ForegroundColor Green
}
catch {
    Write-Host "Error creating/accessing Recovery Services Vault '$RSVname'" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "RBAC PERMISSIONS REQUIRED:" -ForegroundColor Yellow
    Write-Host "  You need 'Backup Contributor' role on the vault:" -ForegroundColor Yellow
    Write-Host "  - Vault: $RSVname" -ForegroundColor Yellow
    Write-Host "  - Resource Group: $BackupResourceGroupName" -ForegroundColor Yellow
    Write-Host "Please contact your Azure administrator to grant these permissions." -ForegroundColor Red
    exit
}

# Step 5: Check VM access:
Write-Host "`nStep 4: Checking VM access..." -ForegroundColor Cyan
$accessibleVMs = @()
foreach ($VMName in $VMNames) {
    try {
        $VM = Get-AzVM -Name $VMName -ResourceGroupName $SourceResourceGroupName -ErrorAction Stop
        $accessibleVMs += $VMName
        Write-Host "VM accessible: $VMName" -ForegroundColor Green
    }
    catch {
        Write-Host "Cannot access VM: $VMName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($accessibleVMs.Count -eq 0) {
    Write-Host "No VMs are accessible. Please check permissions." -ForegroundColor Red
    Write-Host "Required role: 'Virtual Machine Contributor' on the VMs" -ForegroundColor Yellow
    exit
}

# Step 6: Create the backup policy (only if it doesn't exist):
Write-Host "`nStep 5: Creating/verifying backup policy..." -ForegroundColor Cyan
try {
    # Check if policy already exists
    $existingPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $RSVpolicyName -VaultId $vault.ID -ErrorAction SilentlyContinue
    
    if ($existingPolicy) {
        Write-Host "Backup policy '$RSVpolicyName' already exists. Skipping creation." -ForegroundColor Green
        $policy = $existingPolicy
    }
    else {
        Write-Host "Creating new backup policy: $RSVpolicyName" -ForegroundColor Yellow
        
        # Try Enhanced policy first, fall back to standard if needed
        try {
            Write-Host "Attempting to create Enhanced policy..." -ForegroundColor Yellow
            $schedulePolicy = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM -PolicySubType Enhanced -ScheduleRunFrequency Hourly

            # Set timezone - this property should be available in both policy types
            $schedulePolicy.ScheduleRunTimeZone = "GMT Standard Time"
            
            # Try to set enhanced policy properties with error handling
            if ($schedulePolicy.PSObject.Properties.Name -contains "ScheduleWindowStartTime") {
                $schedulePolicy.ScheduleWindowStartTime = (Get-Date "08:00:00").ToUniversalTime()
            } else {
                Write-Host "ScheduleWindowStartTime not available in enhanced policy, using default start time" -ForegroundColor Yellow
            }
            
            if ($schedulePolicy.PSObject.Properties.Name -contains "ScheduleInterval") {
                $schedulePolicy.ScheduleInterval = 4
            }
            
            if ($schedulePolicy.PSObject.Properties.Name -contains "ScheduleWindowDuration") {
                $schedulePolicy.ScheduleWindowDuration = 23
            }

            $retentionPolicy = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM -ScheduleRunFrequency Hourly

            # Set retention - check if property exists
            if ($retentionPolicy.DailySchedule.PSObject.Properties.Name -contains "DurationCountInDays") {
                $retentionPolicy.DailySchedule.DurationCountInDays = 365
            } elseif ($retentionPolicy.PSObject.Properties.Name -contains "DailySchedule") {
                # Alternative property path
                $retentionPolicy.DailySchedule.DurationCountInDays = 365
            }

            $policy = New-AzRecoveryServicesBackupProtectionPolicy -Name $RSVpolicyName -WorkloadType AzureVM -SchedulePolicy $schedulePolicy -RetentionPolicy $retentionPolicy -VaultId $vault.ID
            
            Write-Host "Successfully created Enhanced backup policy: $RSVpolicyName" -ForegroundColor Green
        }
        catch {
            Write-Host "Enhanced policy creation failed, trying standard policy..." -ForegroundColor Yellow
            Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Yellow
            
            # Fall back to standard policy
            $schedulePolicy = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM -ScheduleRunFrequency Hourly
            $schedulePolicy.ScheduleRunTimeZone = "GMT Standard Time"
            
            $retentionPolicy = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM -ScheduleRunFrequency Hourly
            $retentionPolicy.DailySchedule.DurationCountInDays = 365

            $policy = New-AzRecoveryServicesBackupProtectionPolicy -Name $RSVpolicyName -WorkloadType AzureVM -SchedulePolicy $schedulePolicy -RetentionPolicy $retentionPolicy -VaultId $vault.ID
            
            Write-Host "Successfully created Standard backup policy: $RSVpolicyName" -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "Error creating/accessing backup policy: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please check your Azure PowerShell module version and permissions." -ForegroundColor Yellow
    exit
}

# Step 7: Get the policy object (verification):
Write-Host "`nStep 6: Retrieving backup policy..." -ForegroundColor Cyan
try {
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $RSVpolicyName -VaultId $vault.ID

    if (-not $policy) {
        Write-Host "Error: Could not retrieve the backup policy. Exiting." -ForegroundColor Red
        exit
    }
    else {
        Write-Host "Backup policy retrieved successfully" -ForegroundColor Green
        Write-Host "  Policy Name: $($policy.Name)" -ForegroundColor White
        Write-Host "  Workload Type: $($policy.WorkloadType)" -ForegroundColor White
        Write-Host "  Schedule Run Frequency: $($policy.SchedulePolicy.ScheduleRunFrequency)" -ForegroundColor White
        Write-Host "  Policy Type: $($policy.SchedulePolicy.PolicySubType)" -ForegroundColor White
    }
}
catch {
    Write-Host "Error retrieving backup policy: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Step 8: Apply backup policy to VMs:
Write-Host "`nStep 7: Applying backup policy to VMs..." -ForegroundColor Cyan
Write-Host "Starting backup policy assignment to $($accessibleVMs.Count) VMs..." -ForegroundColor Cyan

$successCount = 0
$skipCount = 0
$failCount = 0

foreach ($VMName in $accessibleVMs) {
    Write-Host "Processing: $VMName" -ForegroundColor Yellow
    
    try {
        $backupItem = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM | Where-Object {$_.Name -eq $VMName}
        
        if ($backupItem) {
            Write-Host "Backup already enabled for: $VMName. Skipping..." -ForegroundColor Yellow
            $skipCount++
            continue
        }
        
        Enable-AzRecoveryServicesBackupProtection -Policy $policy -Name $VMName -ResourceGroupName $SourceResourceGroupName -VaultId $vault.ID
            
        Write-Host "Successfully applied backup policy to: $VMName" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "Failed to apply policy to: $VMName - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Final summary
Write-Host "`n" + "="*50 -ForegroundColor Cyan
Write-Host "BACKUP CONFIGURATION SUMMARY" -ForegroundColor Cyan
Write-Host "="*50 -ForegroundColor Cyan
Write-Host "Backup Resource Group: $BackupResourceGroupName" -ForegroundColor White
Write-Host "Recovery Services Vault: $RSVname" -ForegroundColor White
Write-Host "Backup Policy: $RSVpolicyName" -ForegroundColor White
Write-Host "Policy Type: $($policy.SchedulePolicy.PolicySubType)" -ForegroundColor White
Write-Host "Successful: $successCount VMs" -ForegroundColor Green
Write-Host "Skipped: $skipCount VMs (already protected)" -ForegroundColor Yellow
Write-Host "Failed: $failCount VMs" -ForegroundColor Red
Write-Host "Total processed: $($accessibleVMs.Count) VMs" -ForegroundColor White
Write-Host "="*50 -ForegroundColor Cyan