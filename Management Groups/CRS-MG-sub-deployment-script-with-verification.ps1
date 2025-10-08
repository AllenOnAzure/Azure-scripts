<#
# PowerShell Script to Create Management Group Hierarchy and Subscriptions
# Requires Az Module and appropriate permissions

Intelligent Resource Creation
Management Groups: 
Skips creation if already exists
Subscriptions: 
If exists and in correct MG → Skips
If exists but in wrong MG → Moves it
If doesn't exist → Creates new one

######### HOW TO USE THIS SCRIPT: ##########
1. Run the script first - It will create all management groups
2. Create missing subscriptions manually in Azure Portal
3. Re-run the script - It will move the newly created subscriptions to the correct management groups
#>


# Import the Az module
#Import-Module Az

# Connect to Azure (if not already connected)
#Connect-AzAccount

# Set the parent management group
$ParentMG = "CRS-TOP-LEVEL-(intermediate)"

# Function to check if management group exists
function Test-ManagementGroup {
    param([string]$Name)
    
    try {
        $mg = Get-AzManagementGroup -GroupName $Name -ErrorAction SilentlyContinue
        return ($null -ne $mg)
    }
    catch {
        return $false
    }
}

# Function to check if subscription exists
function Test-Subscription {
    param([string]$Name)
    
    try {
        $sub = Get-AzSubscription -SubscriptionName $Name -ErrorAction SilentlyContinue
        return ($null -ne $sub)
    }
    catch {
        return $false
    }
}

# Function to get subscription ID by name
function Get-SubscriptionId {
    param([string]$Name)
    
    try {
        $sub = Get-AzSubscription -SubscriptionName $Name -ErrorAction SilentlyContinue
        return $sub.Id
    }
    catch {
        return $null
    }
}

# Function to create management group
function New-ManagementGroup {
    param(
        [string]$Name,
        [string]$ParentName,
        [string]$DisplayName = $null
    )
    
    if (-not $DisplayName) {
        $DisplayName = $Name
    }
    
    # Check if management group already exists
    if (Test-ManagementGroup -Name $Name) {
        Write-Host "✓ Management group '$Name' already exists." -ForegroundColor Green
        return Get-AzManagementGroup -GroupName $Name
    }
    
    Write-Host "Creating management group: $Name under $ParentName" -ForegroundColor Yellow
    
    try {
        # Check if parent exists
        if (-not (Test-ManagementGroup -Name $ParentName)) {
            Write-Host "Parent management group '$ParentName' not found. Please create it first." -ForegroundColor Red
            return $null
        }
        
        $mg = New-AzManagementGroup -GroupName $Name -DisplayName $DisplayName -ParentId "/providers/Microsoft.Management/managementGroups/$ParentName" -ErrorAction Stop
        Write-Host "✓ Successfully created management group: $Name" -ForegroundColor Green
        return $mg
    }
    catch {
        Write-Host "✗ Error creating management group $Name : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to validate and move subscription to management group
function Register-Subscription {
    param(
        [string]$SubscriptionName,
        [string]$ManagementGroupName
    )
    
    Write-Host "Processing subscription: $SubscriptionName -> $ManagementGroupName" -ForegroundColor Cyan
    
    # Check if management group exists
    if (-not (Test-ManagementGroup -Name $ManagementGroupName)) {
        Write-Host "✗ Management group '$ManagementGroupName' not found. Please create it first." -ForegroundColor Red
        return $false
    }
    
    # Check if subscription exists
    if (Test-Subscription -Name $SubscriptionName) {
        Write-Host "✓ Subscription '$SubscriptionName' exists. Checking management group assignment..." -ForegroundColor Yellow
        
        $existingSub = Get-AzSubscription -SubscriptionName $SubscriptionName
        $subId = $existingSub.Id
        
        # Check if subscription is already in the correct management group
        try {
            $mgSubscriptions = (Get-AzManagementGroup -GroupName $ManagementGroupName -Expand).Children | Where-Object { $_.Type -eq "/subscriptions" }
            $isInCorrectMG = $mgSubscriptions | Where-Object { $_.Name -eq $subId }
            
            if ($isInCorrectMG) {
                Write-Host "✓ Subscription '$SubscriptionName' is already in correct management group '$ManagementGroupName'" -ForegroundColor Green
                return $true
            } else {
                Write-Host "Moving subscription '$SubscriptionName' to management group '$ManagementGroupName'" -ForegroundColor Yellow
                try {
                    New-AzManagementGroupSubscription -GroupName $ManagementGroupName -SubscriptionId $subId -ErrorAction Stop
                    Write-Host "✓ Successfully moved subscription '$SubscriptionName' to '$ManagementGroupName'" -ForegroundColor Green
                    return $true
                }
                catch {
                    Write-Host "✗ Error moving subscription '$SubscriptionName' : $($_.Exception.Message)" -ForegroundColor Red
                    return $false
                }
            }
        }
        catch {
            Write-Host "✗ Error checking management group assignment: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "✗ Subscription '$SubscriptionName' does not exist." -ForegroundColor Red
        Write-Host "  Manual step required:" -ForegroundColor Yellow
        Write-Host "  1. Create subscription '$SubscriptionName' in Azure Portal" -ForegroundColor White
        Write-Host "  2. Run the move command below after creation" -ForegroundColor White
        return $false
    }
}

# Function to wait for management group propagation
function Wait-ForMGPropagation {
    param([int]$Seconds = 10)
    
    Write-Host "Waiting $Seconds seconds for management group propagation..." -ForegroundColor Gray
    Start-Sleep -Seconds $Seconds
}

# Main execution
Write-Host "Starting Management Group Hierarchy Creation..." -ForegroundColor Cyan
Write-Host "Checking existing resources and deploying only what's needed..." -ForegroundColor Yellow

# Step 1: Create first level child management groups under parent
Write-Host "`nStep 1: Creating first-level child management groups..." -ForegroundColor Cyan

$firstLevelMGs = @(
    @{Name = "CRS-Platform"; Parent = $ParentMG},
    @{Name = "CRS-LandingZones"; Parent = $ParentMG},
    @{Name = "CRS-Sandbox"; Parent = $ParentMG},
    @{Name = "CRS-Decommissioned"; Parent = $ParentMG}
)

foreach ($mg in $firstLevelMGs) {
    New-ManagementGroup -Name $mg.Name -ParentName $mg.Parent
}

# Wait for management groups to propagate
Wait-ForMGPropagation -Seconds 10

# Step 2: Create child management groups under CRS-Platform
Write-Host "`nStep 2: Creating child management groups under CRS-Platform..." -ForegroundColor Cyan

$platformChildMGs = @(
    @{Name = "CRS-Management"; Parent = "CRS-Platform"},
    @{Name = "CRS-Identity"; Parent = "CRS-Platform"},
    @{Name = "CRS-Connectivity"; Parent = "CRS-Platform"}
)

foreach ($mg in $platformChildMGs) {
    New-ManagementGroup -Name $mg.Name -ParentName $mg.Parent
}

# Step 3: Create child management groups under CRS-LandingZones
Write-Host "`nStep 3: Creating child management groups under CRS-LandingZones..." -ForegroundColor Cyan

$landingZonesChildMGs = @(
    @{Name = "CRS-Online"; Parent = "CRS-LandingZones"},
    @{Name = "CRS-Corp"; Parent = "CRS-LandingZones"}
)

foreach ($mg in $landingZonesChildMGs) {
    New-ManagementGroup -Name $mg.Name -ParentName $mg.Parent
}

# Wait for management groups to propagate
Wait-ForMGPropagation -Seconds 10

# Step 4: Register subscriptions with their respective management groups
Write-Host "`nStep 4: Registering subscriptions with management groups..." -ForegroundColor Cyan
Write-Host "Note: Subscriptions must be created manually in Azure Portal first." -ForegroundColor Yellow

# Define all subscriptions with their target management groups
$subscriptions = @(
    # Under CRS-Management
    @{Name = "CRS-Management-Prod-001"; MG = "CRS-Management"},
    
    # Under CRS-Identity
    @{Name = "CRS-Identity-Prod-001"; MG = "CRS-Identity"},
    
    # Under CRS-Connectivity
    @{Name = "CRS-Connectivity-Prod-001"; MG = "CRS-Connectivity"},
    @{Name = "CRS-Connectivity-Dev-001"; MG = "CRS-Connectivity"},
    @{Name = "CRS-Security-Prod-001"; MG = "CRS-Connectivity"},
    
    # Under CRS-Online
    @{Name = "CRS-Internet-Prod-001"; MG = "CRS-Online"},
    
    # Under CRS-Corp
    @{Name = "CRS-Workload-Prod-001"; MG = "CRS-Corp"},
    @{Name = "CRS-Workload-Prod-002"; MG = "CRS-Corp"},
    @{Name = "CRS-Workload-Prod-003"; MG = "CRS-Corp"},
    @{Name = "CRS-DataManagement-Prod-001"; MG = "CRS-Corp"},
    @{Name = "CRS-Finance-Dev-001"; MG = "CRS-Corp"},
    
    # Under CRS-Sandbox
    @{Name = "CRS-ACS-Sandbox-Dev-001"; MG = "CRS-Sandbox"},
    @{Name = "CRS-DataManagement-Sandbox-Dev-001"; MG = "CRS-Sandbox"},
    @{Name = "CRS-Workload-Sandbox-Dev-001"; MG = "CRS-Sandbox"}
)

# Group subscriptions by management group for better output
$subscriptionsByMG = $subscriptions | Group-Object MG

$successCount = 0
$failCount = 0
$manualCount = 0

foreach ($mgGroup in $subscriptionsByMG) {
    Write-Host "`n--- Processing subscriptions for $($mgGroup.Name) ---" -ForegroundColor Magenta
    
    foreach ($sub in $mgGroup.Group) {
        $result = Register-Subscription -SubscriptionName $sub.Name -ManagementGroupName $sub.MG
        if ($result) {
            $successCount++
        } else {
            $failCount++
            $manualCount++ # All failures require manual intervention
        }
        Write-Host "" # Empty line for readability
    }
}

# Summary report
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

# Count management groups
$allMGs = @(
    "CRS-Platform", "CRS-LandingZones", "CRS-Sandbox", "CRS-Decommissioned",
    "CRS-Management", "CRS-Identity", "CRS-Connectivity",
    "CRS-Online", "CRS-Corp"
)

$mgCreated = 0
$mgExisting = 0

foreach ($mgName in $allMGs) {
    if (Test-ManagementGroup -Name $mgName) {
        $mgExisting++
    } else {
        $mgCreated++
    }
}

Write-Host "Management Groups:" -ForegroundColor White
Write-Host "  ✓ Created: $mgCreated" -ForegroundColor Green
Write-Host "  ✓ Existing: $mgExisting" -ForegroundColor Yellow
Write-Host "  ✓ Total: $($allMGs.Count)" -ForegroundColor White

Write-Host "`nSubscriptions:" -ForegroundColor White
Write-Host "  ✓ Successfully processed: $successCount" -ForegroundColor Green
Write-Host "  ✗ Need manual creation: $manualCount" -ForegroundColor Red
Write-Host "  ✓ Total subscriptions defined: $($subscriptions.Count)" -ForegroundColor White

Write-Host "`nScript execution completed!" -ForegroundColor Cyan

# Display manual instructions for missing subscriptions
$missingSubs = $subscriptions | Where-Object { -not (Test-Subscription -Name $_.Name) }

if ($missingSubs.Count -gt 0) {
    Write-Host "`n" + "="*60 -ForegroundColor Yellow
    Write-Host "MANUAL STEPS REQUIRED" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Yellow
    Write-Host "The following subscriptions need to be created manually in Azure Portal:" -ForegroundColor White
    
    foreach ($sub in $missingSubs) {
        Write-Host "`nSubscription: $($sub.Name)" -ForegroundColor Cyan
        Write-Host "Target Management Group: $($sub.MG)" -ForegroundColor White
        Write-Host "Steps:" -ForegroundColor White
        Write-Host "  1. Go to Azure Portal → Subscriptions → Create" -ForegroundColor Gray
        Write-Host "  2. Create subscription named: $($sub.Name)" -ForegroundColor Gray
        Write-Host "  3. After creation, run this command:" -ForegroundColor Gray
        Write-Host "     New-AzManagementGroupSubscription -GroupName '$($sub.MG)' -SubscriptionId (Get-AzSubscription -SubscriptionName '$($sub.Name)').Id" -ForegroundColor Green
    }
    
    Write-Host "`nAfter creating all missing subscriptions, you can re-run this script to move them to the correct management groups." -ForegroundColor Yellow
}

# Generate quick commands for all subscriptions
Write-Host "`n" + "="*60 -ForegroundColor Gray
Write-Host "QUICK COMMANDS REFERENCE" -ForegroundColor Gray
Write-Host "="*60 -ForegroundColor Gray
Write-Host "To move any subscription to its management group, use:" -ForegroundColor White

foreach ($sub in $subscriptions) {
    $subId = Get-SubscriptionId -Name $sub.Name
    if ($subId) {
        Write-Host "New-AzManagementGroupSubscription -GroupName '$($sub.MG)' -SubscriptionId '$subId'" -ForegroundColor Green
    } else {
        Write-Host "# $($sub.Name) - Subscription not found" -ForegroundColor Gray
    }
}

Write-Host "`nPlease verify the management group hierarchy and subscriptions in Azure Portal." -ForegroundColor Yellow