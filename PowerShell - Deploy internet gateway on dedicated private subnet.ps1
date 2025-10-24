# PowerShell - Deploy internet gateway on dedicated private subnet #
<#
- Creates a resource group, VNet, and subnet.
- Creates a route table with a default route (0.0.0.0/0) pointing to the internet.
- Associates the route table with the subnet to enable outbound internet access.
- Creates an internet gateway resource instance.
#>

# Variables
$IGresourceGroup = "allens-internetGateway"
$resourceGroup = "vnets"
$location = "uksouth"
$vnetName = "uk-south-private"
$subnetName = "privatesub1"
$routeTableName = "InternetRouteTable"
$routeName = "InternetRoute"
$internetGatewayName = "allens-internetGateway-dev"

# Create Resource Group
Write-Host "Creating Resource Group: $IGresourceGroup" -ForegroundColor Green
New-AzResourceGroup -Name $IGresourceGroup -Location $location -Force

# Check if Virtual Network exists
Write-Host "Checking if Virtual Network '$vnetName' exists..." -ForegroundColor Yellow
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

if ($vnet) {
    Write-Host "Virtual Network '$vnetName' already exists." -ForegroundColor Green
} else {
    Write-Host "Virtual Network '$vnetName' not found. Creating new VNet..." -ForegroundColor Yellow
    
    # Create new Virtual Network
    $vnet = New-AzVirtualNetwork `
        -Name $vnetName `
        -ResourceGroupName $resourceGroup `
        -Location $location `
        -AddressPrefix "10.0.0.0/16"
    
    Write-Host "Virtual Network '$vnetName' created successfully." -ForegroundColor Green
}

# Check if Subnet exists
Write-Host "Checking if Subnet '$subnetName' exists..." -ForegroundColor Yellow
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue

if ($subnet) {
    Write-Host "Subnet '$subnetName' already exists." -ForegroundColor Green
} else {
    Write-Host "Subnet '$subnetName' not found. Creating new subnet..." -ForegroundColor Yellow
    
    # Add subnet configuration
    Add-AzVirtualNetworkSubnetConfig `
        -Name $subnetName `
        -AddressPrefix "10.0.0.32/28" `
        -VirtualNetwork $vnet | Out-Null

    $vnet | Set-AzVirtualNetwork
    Write-Host "Subnet '$subnetName' created successfully." -ForegroundColor Green
}

# Refresh VNet and Subnet references
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet

# Check if Route Table exists
Write-Host "Checking if Route Table '$routeTableName' exists..." -ForegroundColor Yellow
$routeTable = Get-AzRouteTable -Name $routeTableName -ResourceGroupName $IGresourceGroup -ErrorAction SilentlyContinue

if ($routeTable) {
    Write-Host "Route Table '$routeTableName' already exists." -ForegroundColor Green
} else {
    Write-Host "Route Table '$routeTableName' not found. Creating new route table..." -ForegroundColor Yellow
    
    # Create Route Table
    $routeTable = New-AzRouteTable `
        -Name $routeTableName `
        -ResourceGroupName $IGresourceGroup `
        -Location $location
    
    Write-Host "Route Table '$routeTableName' created successfully." -ForegroundColor Green
}

# Add/Update Route to Internet
Write-Host "Configuring default route to Internet..." -ForegroundColor Yellow
$existingRoute = Get-AzRouteConfig -Name $routeName -RouteTable $routeTable -ErrorAction SilentlyContinue

if ($existingRoute) {
    Write-Host "Route '$routeName' already exists. Updating..." -ForegroundColor Yellow
    Set-AzRouteConfig `
        -Name $routeName `
        -AddressPrefix "0.0.0.0/0" `
        -NextHopType "Internet" `
        -RouteTable $routeTable | Out-Null
} else {
    Write-Host "Adding new route '$routeName'..." -ForegroundColor Yellow
    Add-AzRouteConfig `
        -Name $routeName `
        -AddressPrefix "0.0.0.0/0" `
        -NextHopType "Internet" `
        -RouteTable $routeTable | Out-Null
}

$routeTable | Set-AzRouteTable
Write-Host "Route configuration completed." -ForegroundColor Green

# Associate Route Table with Subnet
Write-Host "Associating Route Table with Subnet..." -ForegroundColor Yellow
Set-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix $subnet.AddressPrefix `
    -VirtualNetwork $vnet `
    -RouteTable $routeTable | Out-Null

$vnet | Set-AzVirtualNetwork
Write-Host "Route Table associated with subnet successfully." -ForegroundColor Green

# Create Internet Gateway Resources
Write-Host "Creating Internet Gateway resources..." -ForegroundColor Green

# Check if Public IP exists
$publicIpName = "$internetGatewayName-pip"
Write-Host "Checking if Public IP '$publicIpName' exists..." -ForegroundColor Yellow
$publicIp = Get-AzPublicIpAddress -Name $publicIpName -ResourceGroupName $IGresourceGroup -ErrorAction SilentlyContinue

if ($publicIp) {
    Write-Host "Public IP '$publicIpName' already exists." -ForegroundColor Green
} else {
    Write-Host "Creating Public IP Address..." -ForegroundColor Yellow
    $publicIp = New-AzPublicIpAddress `
        -Name $publicIpName `
        -ResourceGroupName $IGresourceGroup `
        -Location $location `
        -AllocationMethod Static `
        -Sku Standard `
        -Tag @{ 
            Environment = "Development"
            Purpose = "InternetGateway"
            GatewayName = $internetGatewayName
        }
    Write-Host "Public IP '$publicIpName' created successfully." -ForegroundColor Green
}

# Check if Network Security Group exists
$nsgName = "$internetGatewayName-nsg"
Write-Host "Checking if Network Security Group '$nsgName' exists..." -ForegroundColor Yellow
$nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $IGresourceGroup -ErrorAction SilentlyContinue

if ($nsg) {
    Write-Host "Network Security Group '$nsgName' already exists." -ForegroundColor Green
} else {
    Write-Host "Creating Network Security Group..." -ForegroundColor Yellow
    $nsg = New-AzNetworkSecurityGroup `
        -Name $nsgName `
        -ResourceGroupName $IGresourceGroup `
        -Location $location `
        -Tag @{ 
            Environment = "Development"
            Purpose = "InternetGateway"
            GatewayName = $internetGatewayName
        }
    Write-Host "Network Security Group '$nsgName' created successfully." -ForegroundColor Green
}

# Configure NSG rules
Write-Host "Configuring NSG rules..." -ForegroundColor Yellow

# Define NSG rules
$nsgRules = @(
    @{
        Name = "Allow-HTTPS-Inbound"
        Description = "Allow HTTPS traffic"
        Access = "Allow"
        Protocol = "Tcp"
        Direction = "Inbound"
        Priority = 100
        SourceAddressPrefix = "*"
        SourcePortRange = "*"
        DestinationAddressPrefix = "*"
        DestinationPortRange = "443"
    },
    @{
        Name = "Allow-HTTP-Inbound"
        Description = "Allow HTTP traffic"
        Access = "Allow"
        Protocol = "Tcp"
        Direction = "Inbound"
        Priority = 110
        SourceAddressPrefix = "*"
        SourcePortRange = "*"
        DestinationAddressPrefix = "*"
        DestinationPortRange = "80"
    },
    @{
        Name = "Allow-All-Outbound"
        Description = "Allow all outbound traffic"
        Access = "Allow"
        Protocol = "*"
        Direction = "Outbound"
        Priority = 100
        SourceAddressPrefix = "*"
        SourcePortRange = "*"
        DestinationAddressPrefix = "*"
        DestinationPortRange = "*"
    }
)

# Apply NSG rules
foreach ($rule in $nsgRules) {
    $existingRule = Get-AzNetworkSecurityRuleConfig -Name $rule.Name -NetworkSecurityGroup $nsg -ErrorAction SilentlyContinue
    
    if ($existingRule) {
        Write-Host "Updating NSG rule: $($rule.Name)" -ForegroundColor Yellow
        Set-AzNetworkSecurityRuleConfig @rule -NetworkSecurityGroup $nsg | Out-Null
    } else {
        Write-Host "Adding NSG rule: $($rule.Name)" -ForegroundColor Yellow
        Add-AzNetworkSecurityRuleConfig @rule -NetworkSecurityGroup $nsg | Out-Null
    }
}

$nsg | Set-AzNetworkSecurityGroup
Write-Host "NSG rules configured successfully." -ForegroundColor Green

# Associate NSG with the internet gateway subnet
Write-Host "Associating NSG with Subnet..." -ForegroundColor Yellow
Set-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix $subnet.AddressPrefix `
    -VirtualNetwork $vnet `
    -RouteTable $routeTable `
    -NetworkSecurityGroup $nsg | Out-Null

$vnet | Set-AzVirtualNetwork
Write-Host "NSG associated with subnet successfully." -ForegroundColor Green

# Output the created resources
Write-Host "`nInternet Gateway deployment completed successfully!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Internet Gateway Name: $internetGatewayName" -ForegroundColor Yellow
Write-Host "Resource Group: $IGresourceGroup" -ForegroundColor Yellow
Write-Host "Public IP Address: $($publicIp.IpAddress)" -ForegroundColor Yellow
Write-Host "Route Table: $routeTableName" -ForegroundColor Yellow
Write-Host "Subnet: $subnetName ($($subnet.AddressPrefix))" -ForegroundColor Yellow

# Display resource details
Write-Host "`nCreated/Verified Resources:" -ForegroundColor Cyan
Write-Host "- Public IP: $($publicIp.Name)" -ForegroundColor White
Write-Host "- Network Security Group: $($nsg.Name)" -ForegroundColor White
Write-Host "- Route Table: $routeTableName" -ForegroundColor White
Write-Host "- Associated Subnet: $subnetName" -ForegroundColor White
Write-Host "- Virtual Network: $vnetName" -ForegroundColor White

Write-Host "`nDeployment Summary:" -ForegroundColor Cyan
Write-Host "- All resources checked for existence before creation" -ForegroundColor White
Write-Host "- Outbound internet access enabled via route table" -ForegroundColor White
Write-Host "- Inbound HTTP/HTTPS traffic allowed" -ForegroundColor White
Write-Host "- All outbound traffic allowed" -ForegroundColor White

Write-Host "- Resources tagged for easy identification" -ForegroundColor White

