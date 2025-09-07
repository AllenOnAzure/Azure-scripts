#Create NAT Gateway and associating it with the subnet:

# Connect to Azure (uncomment if needed)
# Connect-AzAccount

# Variables
$resourceGroupName = "vnet-rg"
$location = "uksouth"
$vnetName = "vnet-test"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetName = "subnet1"
$subnetAddressPrefix = "10.0.0.0/26"
$natGatewayName = "gateway1"
$publicIpName = "nat-gateway-ip"
$vnetTag = @{Environment="Test"}

# Create resource group if it doesn't exist
$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
    Write-Host "Resource group '$resourceGroupName' created successfully."
} else {
    Write-Host "Resource group '$resourceGroupName' already exists."
}

# Create a public IP for the NAT Gateway
$publicIp = New-AzPublicIpAddress -Name $publicIpName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AllocationMethod Static `
    -Sku Standard

Write-Host "Public IP '$publicIpName' created successfully."

# Create NAT Gateway
$natGateway = New-AzNatGateway `
    -Name $natGatewayName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -PublicIpAddress $publicIp `
    -Sku Standard `
    -IdleTimeoutInMinutes 4

Write-Host "NAT Gateway '$natGatewayName' created successfully."

# Create virtual network configuration
$vnetParams = @{
    Name              = $vnetName
    ResourceGroupName = $resourceGroupName
    Location          = $location
    AddressPrefix     = $vnetAddressPrefix
    Tag               = $vnetTag
}

# Create or update virtual network
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $vnet) {
    $vnet = New-AzVirtualNetwork @vnetParams
    Write-Host "Virtual network '$vnetName' created successfully."
} else {
    Set-AzVirtualNetwork -VirtualNetwork $vnet
    Write-Host "Virtual network '$vnetName' updated successfully."
}

# Create subnet configuration with service endpoint
$subnetConfig = Add-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -VirtualNetwork $vnet `
    -AddressPrefix $subnetAddressPrefix `
	-DefaultOutboundAccess $false
	
	

# Associate the subnet configuration to the virtual network
$vnet | Set-AzVirtualNetwork

# Associate NAT Gateway with subnet
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName
$subnet.NatGateway = $natGateway
$vnet | Set-AzVirtualNetwork

# Make subnet private by ensuring no public IP resources are attached directly to VMs
# This is enforced through architecture rather than a specific parameter
Write-Host "Private subnet '$subnetName' with prefix '$subnetAddressPrefix' created successfully."
Write-Host "NOTE: To ensure this remains a private subnet:"
Write-Host "1. Do NOT assign public IP addresses directly to VMs in this subnet"
Write-Host "2. All outbound internet traffic will flow through the NAT Gateway '$natGatewayName'"
Write-Host "3. Use NSGs to control traffic flow as needed"

Write-Host "All resources deployed successfully."

# Display NAT Gateway information
Write-Host "`nNAT Gateway Details:"
Write-Host "Name: $natGatewayName"
Write-Host "Public IP: $($publicIp.IpAddress)"
Write-Host "Associated with subnet: $subnetName"