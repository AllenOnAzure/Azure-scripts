# List of VM names
$vmNames = @("Linux-VM01", "Linux-VM02")

# Common configuration
$location = "uksouth"
$resourceGroupName = "allens-linux-vms"
$adminUsername = "Allen"
$adminPassword = "P@ssw0rd1"
$vmSize = "Standard_B2s"

# Central Storage Account for Boot Diagnostics (add these lines)
$bootDiagStorageAccountName = "allensbootdiagstorage"  # Must be globally unique
$bootDiagStorageSku = "Standard_LRS"

# Login to Azure
Connect-AzAccount

# Create the shared resource group
if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

# Create or get the central boot diagnostics storage account
$bootDiagStorageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $bootDiagStorageAccountName -ErrorAction SilentlyContinue
if (-not $bootDiagStorageAccount) {
    $bootDiagStorageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroupName `
        -Name $bootDiagStorageAccountName -Location $location `
        -SkuName $bootDiagStorageSku -Kind "StorageV2"
}

foreach ($vmName in $vmNames) {
    Write-Host "Deploying VM: $vmName"

    # Create VNet and subnet
    $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name "${vmName}-subnet" -AddressPrefix "10.0.1.0/24"
    $vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location `
        -Name "${vmName}-vnet" -AddressPrefix "10.0.0.0/16" -Subnet $subnetConfig

    # Create public IP
    $publicIp = New-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Location $location `
        -Name "${vmName}-pip" -AllocationMethod Dynamic -Sku Basic

    # Create NSG and SSH rule
    $nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name "${vmName}-allow-ssh" -Protocol Tcp -Direction Inbound `
        -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
        -DestinationPortRange 22 -Access Allow
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location `
        -Name "${vmName}-nsg" -SecurityRules $nsgRuleSSH

    # Create NIC
    $nic = New-AzNetworkInterface -Name "${vmName}-nic" -ResourceGroupName $resourceGroupName `
        -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIp.Id `
        -NetworkSecurityGroupId $nsg.Id

    # VM credentials
    $securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $securePassword)

    # VM configuration
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize | 
        Set-AzVMOperatingSystem -Linux -ComputerName $vmName -Credential $credential | 
        Set-AzVMSourceImage -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" `
            -Skus "22_04-lts-gen2" -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id

    # Configure boot diagnostics to use our central storage account
    Set-AzVMBootDiagnostic -VM $vmConfig -Enable -ResourceGroupName $resourceGroupName `
        -StorageAccountName $bootDiagStorageAccountName

    # Create VM
    New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig

    Write-Host "✅ $vmName deployed successfully!"
    Write-Host "SSH command: ssh ${adminUsername}@$($publicIp.IpAddress)"
    Write-Host "Boot Diagnostics Storage: $($bootDiagStorageAccount.PrimaryEndpoints.Blob)"
    Write-Host "---------------------------------------------"
}