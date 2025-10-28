# PowerShell - Enhanced Backup Policy for ALL VMs in Subscription #

# Step 0: Define your configuration
$BackupResourceGroupName = "vm-backups"
$RSVname = "AllensSubsBackupVault"
$RSVpolicyName = "Allens-Enhanced-Hourly-Backup-Policy"


# Optional: Define filters for VMs (comment out if not needed)
$FilterByEnvironment = $true  # Set to $false to disable environment filtering
$EnvironmentTagValue = "Production"  # Only backup VMs with this environment tag

$FilterByNamePattern = $false  # Set to $true to enable name pattern filtering
$NamePattern = "*-PROD-*"     # Pattern to match in VM names

$FilterByExclusion = $false    # Set to $false to disable exclusion filtering
$ExcludePatterns = @("*TEST*", "*DEV*", "*STAGING*")  # VMs with these patterns will be excluded

Write-Host "Starting Azure Backup Configuration for ALL VMs in Subscription..." -ForegroundColor Cyan
Write-Host "Backup Resource Group: $BackupResourceGroupName" -ForegroundColor Yellow
Write-Host "Vault Name: $RSVname" -ForegroundColor Yellow
Write-Host "Processing ALL VMs in subscription with filtering" -ForegroundColor Yellow

if ($FilterByEnvironment) {
    Write-Host "Environment Filter: Only VMs with tag 'Environment=$EnvironmentTagValue'" -ForegroundColor Yellow
}
if ($FilterByNamePattern) {
    Write-Host "Name Pattern Filter: Only VMs matching: $NamePattern" -ForegroundColor Yellow
}
if ($FilterByExclusion) {
    Write-Host "Exclusion Patterns: Excluding VMs with: $($ExcludePatterns -join ', ')" -ForegroundColor Yellow
}

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

# Step 2: Create or verify backup resource group
Write-Host "`nStep 2: Creating/verifying backup resource group..." -ForegroundColor Cyan
try {
    $backupRG = Get-AzResourceGroup -Name $BackupResourceGroupName -ErrorAction SilentlyContinue
    
    if (-not $backupRG) {
        Write-Host "Backup resource group '$BackupResourceGroupName' not found. Creating new one..." -ForegroundColor Yellow
        
        # Choose a default location for the backup resource group
        $location = "East US"  # Change to your preferred default location
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

# Step 3: Create or verify Recovery Services Vault
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

# Step 4: Get ALL VMs in the subscription with filtering
Write-Host "`nStep 4: Retrieving ALL VMs from subscription with filtering..." -ForegroundColor Cyan
try {
    $AllVMs = Get-AzVM -ErrorAction Stop
    $filteredVMs = @()
    
    Write-Host "Total VMs found in subscription: $($AllVMs.Count)" -ForegroundColor White
    
    foreach ($VM in $AllVMs) {
        $includeVM = $true
        
        # Apply environment tag filter
        if ($FilterByEnvironment) {
            if ($VM.Tags.Environment -ne $EnvironmentTagValue) {
                Write-Host "Skipping VM (environment tag mismatch): $($VM.Name)" -ForegroundColor Gray
                $includeVM = $false
                continue
            }
        }
        
        # Apply name pattern filter
        if ($FilterByNamePattern -and $includeVM) {
            if ($VM.Name -notlike $NamePattern) {
                Write-Host "Skipping VM (name pattern mismatch): $($VM.Name)" -ForegroundColor Gray
                $includeVM = $false
                continue
            }
        }
        
        # Apply exclusion patterns
        if ($FilterByExclusion -and $includeVM) {
            foreach ($pattern in $ExcludePatterns) {
                if ($VM.Name -like $pattern) {
                    Write-Host "Skipping VM (exclusion pattern match): $($VM.Name)" -ForegroundColor Gray
                    $includeVM = $false
                    break
                }
            }
        }
        
        if ($includeVM) {
            $filteredVMs += $VM
            Write-Host "VM included for backup: $($VM.Name) in $($VM.ResourceGroupName)" -ForegroundColor Green
        }
    }
    
    if ($filteredVMs.Count -eq 0) {
        Write-Host "No VMs matched the filtering criteria." -ForegroundColor Yellow
        Write-Host "Please adjust your filter settings or disable filtering." -ForegroundColor Yellow
        exit
    }
    
    Write-Host "Total VMs after filtering: $($filteredVMs.Count)" -ForegroundColor Green
}
catch {
    Write-Host "Error retrieving VMs from subscription: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Required role: 'Reader' on subscription level" -ForegroundColor Yellow
    exit
}

# Step 5: Create the backup policy (only if it doesn't exist)
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

# Step 6: Get the policy object (verification)
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

# Step 7: Apply backup policy to filtered VMs
Write-Host "`nStep 7: Applying backup policy to filtered VMs..." -ForegroundColor Cyan
Write-Host "Starting backup policy assignment to $($filteredVMs.Count) filtered VMs..." -ForegroundColor Cyan

$successCount = 0
$skipCount = 0
$failCount = 0

foreach ($VM in $filteredVMs) {
    Write-Host "Processing: $($VM.Name) in $($VM.ResourceGroupName)" -ForegroundColor Yellow
    
    try {
        $backupItem = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM | Where-Object {$_.Name -eq $VM.Name}
        
        if ($backupItem) {
            Write-Host "Backup already enabled for: $($VM.Name). Skipping..." -ForegroundColor Yellow
            $skipCount++
            continue
        }
        
        Enable-AzRecoveryServicesBackupProtection -Policy $policy -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -VaultId $vault.ID
            
        Write-Host "Successfully applied backup policy to: $($VM.Name)" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "Failed to apply policy to: $($VM.Name) - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Final summary
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "SUBSCRIPTION BACKUP CONFIGURATION SUMMARY" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "Backup Resource Group: $BackupResourceGroupName" -ForegroundColor White
Write-Host "Recovery Services Vault: $RSVname" -ForegroundColor White
Write-Host "Backup Policy: $RSVpolicyName" -ForegroundColor White
Write-Host "Policy Type: $($policy.SchedulePolicy.PolicySubType)" -ForegroundColor White
Write-Host "Total VMs in subscription: $($AllVMs.Count)" -ForegroundColor White
Write-Host "VMs after filtering: $($filteredVMs.Count)" -ForegroundColor White
Write-Host "Successful: $successCount VMs" -ForegroundColor Green
Write-Host "Skipped: $skipCount VMs (already protected)" -ForegroundColor Yellow
Write-Host "Failed: $failCount VMs" -ForegroundColor Red
Write-Host "="*60 -ForegroundColor Cyan

# Warning for large-scale operations
if ($filteredVMs.Count -gt 50) {
    Write-Host "`n⚠️  WARNING: Large-scale operation detected!" -ForegroundColor Red
    Write-Host "You are configuring backup for $($filteredVMs.Count) VMs." -ForegroundColor Yellow
    Write-Host "This may take significant time and incur substantial costs." -ForegroundColor Yellow
    Write-Host "Monitor your backup vault and storage costs in Azure Portal." -ForegroundColor Yellow
}