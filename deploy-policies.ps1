# Azure Policy Deployment Script (PowerShell)
# This script deploys the two custom policies for managing Defender for Servers on Arc machines

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ManagementGroupId,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseManagementGroup
)

# Check if Az module is installed
if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
    Write-Error "Az.Resources module is not installed. Please install it with: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
    exit 1
}

# Check if logged in
try {
    $currentContext = Get-AzContext
    if (-not $currentContext) {
        Write-Error "Not logged in to Azure. Please run 'Connect-AzAccount' first."
        exit 1
    }
} catch {
    Write-Error "Not logged in to Azure. Please run 'Connect-AzAccount' first."
    exit 1
}

Write-Host "=== Azure Policy Deployment for Arc Free by Tag ===" -ForegroundColor Cyan
Write-Host ""

# Determine scope
if ($UseManagementGroup -or $ManagementGroupId) {
    if (-not $ManagementGroupId) {
        $ManagementGroupId = Read-Host "Enter Management Group ID"
    }
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
    $scopeType = "ManagementGroup"
    Write-Host "Deploying to Management Group: $ManagementGroupId" -ForegroundColor Yellow
} else {
    if (-not $SubscriptionId) {
        $SubscriptionId = $currentContext.Subscription.Id
    }
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $scope = "/subscriptions/$SubscriptionId"
    $scopeType = "Subscription"
    Write-Host "Deploying to Subscription: $SubscriptionId" -ForegroundColor Yellow
}

Write-Host ""

# Load policy definitions
$policy1Path = Join-Path $PSScriptRoot "policies/inherit-tag-from-rg.json"
$policy2Path = Join-Path $PSScriptRoot "policies/disable-defender-arc-by-tag.json"

if (-not (Test-Path $policy1Path)) {
    Write-Error "Policy 1 definition not found at: $policy1Path"
    exit 1
}

if (-not (Test-Path $policy2Path)) {
    Write-Error "Policy 2 definition not found at: $policy2Path"
    exit 1
}

$policy1Definition = Get-Content $policy1Path -Raw | ConvertFrom-Json
$policy2Definition = Get-Content $policy2Path -Raw | ConvertFrom-Json

# Deploy Policy 1: Inherit Tag from Resource Group
Write-Host "=== Deploying Policy 1: Inherit Tag from Resource Group ===" -ForegroundColor Cyan
$policy1Name = "inherit-defenderforservers-tag-from-rg"
$policy1DisplayName = "Inherit DefenderForServers tag from resource group"

try {
    if ($scopeType -eq "ManagementGroup") {
        New-AzPolicyDefinition `
            -Name $policy1Name `
            -DisplayName $policy1DisplayName `
            -ManagementGroupName $ManagementGroupId `
            -Policy ($policy1Definition | ConvertTo-Json -Depth 100) `
            -Mode Indexed `
            -Metadata ($policy1Definition.metadata | ConvertTo-Json -Depth 10) | Out-Null
    } else {
        New-AzPolicyDefinition `
            -Name $policy1Name `
            -DisplayName $policy1DisplayName `
            -SubscriptionId $SubscriptionId `
            -Policy ($policy1Definition | ConvertTo-Json -Depth 100) `
            -Mode Indexed `
            -Metadata ($policy1Definition.metadata | ConvertTo-Json -Depth 10) | Out-Null
    }
    Write-Host "✓ Policy 1 deployed successfully" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*already exists*") {
        Write-Warning "Policy 1 already exists, skipping..."
    } else {
        Write-Error "Failed to deploy Policy 1: $_"
        exit 1
    }
}

Write-Host ""

# Deploy Policy 2: Disable Defender for Servers on Arc by Tag
Write-Host "=== Deploying Policy 2: Disable Defender for Servers on Arc by Tag ===" -ForegroundColor Cyan
$policy2Name = "disable-defender-arc-by-tag"
$policy2DisplayName = "Disable Defender for Servers on Arc machines with DefenderForServers=Disabled tag"

try {
    if ($scopeType -eq "ManagementGroup") {
        New-AzPolicyDefinition `
            -Name $policy2Name `
            -DisplayName $policy2DisplayName `
            -ManagementGroupName $ManagementGroupId `
            -Policy ($policy2Definition | ConvertTo-Json -Depth 100) `
            -Mode Indexed `
            -Metadata ($policy2Definition.metadata | ConvertTo-Json -Depth 10) | Out-Null
    } else {
        New-AzPolicyDefinition `
            -Name $policy2Name `
            -DisplayName $policy2DisplayName `
            -SubscriptionId $SubscriptionId `
            -Policy ($policy2Definition | ConvertTo-Json -Depth 100) `
            -Mode Indexed `
            -Metadata ($policy2Definition.metadata | ConvertTo-Json -Depth 10) | Out-Null
    }
    Write-Host "✓ Policy 2 deployed successfully" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*already exists*") {
        Write-Warning "Policy 2 already exists, skipping..."
    } else {
        Write-Error "Failed to deploy Policy 2: $_"
        exit 1
    }
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Assign Policy 1 ('$policy1Name') to your desired scope (subscription/resource group)"
Write-Host "2. Assign Policy 2 ('$policy2Name') to your subscription"
Write-Host "3. Enable remediation tasks for both policies to apply them to existing resources"
Write-Host "4. Add the tag 'DefenderForServers=Disabled' to resource groups containing Arc machines you want on Free tier"
Write-Host ""
Write-Host "Example assignment commands:" -ForegroundColor Yellow
Write-Host "  New-AzPolicyAssignment -Name 'assign-inherit-tag' -PolicyDefinition (Get-AzPolicyDefinition -Name '$policy1Name') -Scope '$scope'"
Write-Host "  New-AzPolicyAssignment -Name 'assign-disable-defender-arc' -PolicyDefinition (Get-AzPolicyDefinition -Name '$policy2Name') -Scope '$scope' -Location <region> -AssignIdentity"
Write-Host ""
