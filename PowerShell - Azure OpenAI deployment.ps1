# ===============================
# Azure OpenAI Deployment Script
# ===============================

# Parameters
$subscriptionId = "<subID>"
$resourceGroupName = "rg-openai-demo"
$location = "uksouth"
$deploymentName = "openai-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$bicepFilePath = ".\main.bicep"  # Explicit Bicep file path

# Template Parameters
$templateParams = @{
    aiserviceaccountname = "openai-instance"
    modeldeploymentname  = "gpt4turbo-deployment"
    model                = "gpt-4"
    modelversion         = "turbo-2024-04-09"
    capacity             = 80
    sku                  = "S0"
    location             = $location
    tags                 = @{
        Environment = "Dev"
        Owner       = "Allen"
        CostCenter  = "AI-001"
    }
}

try {
    # Login and set subscription
    Write-Host "🔐 Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount -ErrorAction Stop
    
    Write-Host "📋 Setting subscription context..." -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop

    # Validate Bicep file exists
    if (-not (Test-Path $bicepFilePath)) {
        throw "Bicep file not found: $bicepFilePath"
    }

    # Create Resource Group if not exists
    if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
        Write-Host "📦 Creating resource group: $resourceGroupName" -ForegroundColor Green
        New-AzResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop
    } else {
        Write-Host "📦 Using existing resource group: $resourceGroupName" -ForegroundColor Blue
    }

    # Deploy Bicep template
    Write-Host "🚀 Deploying Azure OpenAI instance..." -ForegroundColor Yellow
    $deployment = New-AzResourceGroupDeployment `
        -Name $deploymentName `
        -ResourceGroupName $resourceGroupName `
        -TemplateFile $bicepFilePath `
        -TemplateParameterObject $templateParams `
        -ErrorAction Stop

    Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host "📊 Deployment Outputs:" -ForegroundColor Cyan
    $deployment.Outputs | Format-Table

} catch {
    Write-Host "❌ Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "🎯 Script execution completed." -ForegroundColor Green
