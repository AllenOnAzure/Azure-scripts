### PowerShell - Deploy Windows Virtual Machines at Scale with Trusted Launch Support ###

<#
This script deploys Windows Server 2022 Gen2 image at scale dependent on $vmCount,
The logon credentials are included in the script,
The VMSize is "Standard_B2s" based on frugality,
Azure Monitor Agent is installed, 
Windows automatic Windows updates is enabled, 
StandardSSD_LRS disk is provisioned,
TrustedLaunch is enabled,
EnableSecureBoot is enabled,
#>
	
	
# Set subscription
Set-AzContext -Subscription "<Subscription ID>" #Destination Subscription

# Configuration
$ResourceGroupName = "allen-Windows-vm"
$location = "uksouth"
$vmPrefix = "Wintest"
$vmCount = 3
$vnetResourceGroupName = "vnets"
$vnetName = "vnet-uksouth"
$subnetName = "vm"


# Network configuration
#Dont edit these values!
$vnet = Get-AzVirtualNetwork `
	-ResourceGroupName $vnetResourceGroupName `
	-Name $vnetName
$subnet = Get-AzVirtualNetworkSubnetConfig `
	-VirtualNetwork $vnet `
	-Name $subnetName

# Create Resource Group with tags
New-AzResourceGroup -Name $ResourceGroupName -Location $location `
    -Tag @{
        CustomerName = "Customer01"
        AutoShutdownSchedule = "None"
        Environment = "dev"
		"Deployed By" = "Allen"
    }

# Credentials
$adminUsername = "Allen"
$adminPassword = ConvertTo-SecureString "P@ssword01" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)

# Get the latest supported Windows Server 2022 Gen2 image
$image = Get-AzVMImage `
    -PublisherName "MicrosoftWindowsServer" `
    -Offer "WindowsServer" `
    -Skus "2022-datacenter-g2" `
    -Location $location | 
    Sort-Object -Property PublishedDate -Descending | 
    Select-Object -First 1

# Deploy VMs with Trusted Launch support
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix$i"
    $nicName = "${vmName}-nic"
    
    Write-Host "Creating VM: $vmName"
    
    # Create NIC
    $nic = New-AzNetworkInterface `
        -Name $nicName `
        -ResourceGroupName $ResourceGroupName `
        -Location $location `
        -Subnet $subnet
    
    # VM Configuration with Trusted Launch
    $vmConfig = New-AzVMConfig `
        -VMName $vmName `
        -VMSize "Standard_B2s"
    
    # Set OS configuration
    $vmConfig = Set-AzVMOperatingSystem `
        -VM $vmConfig `
        -Windows `
        -ComputerName $vmName `
        -Credential $credential `
        -ProvisionVMAgent `
        -EnableAutoUpdate
    
    # Set image using explicit version
    $vmConfig = Set-AzVMSourceImage `
        -VM $vmConfig `
        -PublisherName $image.PublisherName `
        -Offer $image.Offer `
        -Skus $image.Skus `
        -Version $image.Version
    
    # Add remaining configurations
    $vmConfig = Add-AzVMNetworkInterface `
        -VM $vmConfig `
        -Id $nic.Id
    
    $vmConfig = Set-AzVMBootDiagnostic `
        -VM $vmConfig `
        -Disable
    
    $vmConfig = Set-AzVMOSDisk `
        -VM $vmConfig `
        -StorageAccountType "StandardSSD_LRS" `
        -CreateOption "FromImage"
    
    $vmConfig = Set-AzVMSecurityProfile `
        -VM $vmConfig `
        -SecurityType "TrustedLaunch"
    
    $vmConfig = Set-AzVmUefi `
        -VM $vmConfig `
        -EnableVtpm $true `
        -EnableSecureBoot $true
    
    # Create VM
    New-AzVM `
        -ResourceGroupName $ResourceGroupName `
        -Location $location `
        -VM $vmConfig `
        -Tag @{
            CustomerName = "Customer01"
            AutoShutdownSchedule = "None"
            Environment = "sandbox"
        }
    
    Write-Host "Successfully deployed $vmName with Trusted Launch security"
    Write-Host "---------------------------------------------"
}

Write-Host "All $vmCount VMs deployed successfully!"

