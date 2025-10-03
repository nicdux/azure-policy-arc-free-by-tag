# Azure Automation Setup Guide

This guide explains how to deploy the Azure Automation runbook that automatically disables Defender for Servers on Arc machines tagged with `DefenderForServers=Disabled`.

## Overview

The solution consists of:
1. **Azure Policies** - Tag inheritance and identification of Arc machines
2. **Azure Automation Runbook** - Removal of Defender agents from tagged Arc machines

## Prerequisites

- Azure Automation Account
- System-assigned Managed Identity enabled on the Automation Account
- Required Azure PowerShell modules in the Automation Account
- Appropriate RBAC permissions for the Managed Identity

## Step 1: Create Azure Automation Account

### Via Azure Portal
1. Navigate to **Azure Portal** > **Automation Accounts**
2. Click **+ Create**
3. Fill in the details:
   - **Name**: `aa-defender-arc-automation` (or your preferred name)
   - **Resource Group**: Create new or select existing
   - **Region**: Select your preferred region
   - **Enable system assigned managed identity**: **Yes** (Important!)
4. Click **Review + Create**, then **Create**

### Via Azure CLI
```bash
# Variables
RG_NAME="rg-defender-automation"
AA_NAME="aa-defender-arc-automation"
LOCATION="westeurope"

# Create Resource Group
az group create --name $RG_NAME --location $LOCATION

# Create Automation Account
az automation account create \
  --name $AA_NAME \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --assign-identity

# Get the Managed Identity Principal ID
IDENTITY_ID=$(az automation account show \
  --name $AA_NAME \
  --resource-group $RG_NAME \
  --query identity.principalId -o tsv)

echo "Managed Identity Principal ID: $IDENTITY_ID"
```

### Via PowerShell
```powershell
# Variables
$rgName = "rg-defender-automation"
$aaName = "aa-defender-arc-automation"
$location = "westeurope"

# Create Resource Group
New-AzResourceGroup -Name $rgName -Location $location

# Create Automation Account with Managed Identity
New-AzAutomationAccount `
  -Name $aaName `
  -ResourceGroupName $rgName `
  -Location $location `
  -AssignSystemIdentity

# Get the Managed Identity Principal ID
$aa = Get-AzAutomationAccount -Name $aaName -ResourceGroupName $rgName
$identityId = $aa.Identity.PrincipalId
Write-Host "Managed Identity Principal ID: $identityId"
```

## Step 2: Assign RBAC Permissions

The Managed Identity needs the following permissions:

### Required Roles
1. **Reader** - On subscription (to query Arc machines)
2. **Hybrid Compute Contributor** - On subscription or specific RGs (to manage Arc machine extensions)
3. **Security Admin** - On subscription (to modify Defender settings, optional)

### Assign via Azure CLI
```bash
# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign Reader role
az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Assign Azure Connected Machine Resource Administrator role
az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Azure Connected Machine Resource Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Optional: Assign Security Admin role
az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Security Admin" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Assign via PowerShell
```powershell
# Get subscription ID
$subscriptionId = (Get-AzContext).Subscription.Id

# Assign Reader role
New-AzRoleAssignment `
  -ObjectId $identityId `
  -RoleDefinitionName "Reader" `
  -Scope "/subscriptions/$subscriptionId"

# Assign Azure Connected Machine Resource Administrator role
New-AzRoleAssignment `
  -ObjectId $identityId `
  -RoleDefinitionName "Azure Connected Machine Resource Administrator" `
  -Scope "/subscriptions/$subscriptionId"

# Optional: Assign Security Admin role
New-AzRoleAssignment `
  -ObjectId $identityId `
  -RoleDefinitionName "Security Admin" `
  -Scope "/subscriptions/$subscriptionId"
```

## Step 3: Import Required Modules

The runbook requires the following PowerShell modules:

### Via Azure Portal
1. Navigate to your Automation Account
2. Go to **Modules** > **Browse Gallery**
3. Search and import these modules **in order**:
   - `Az.Accounts` (import first)
   - `Az.Resources`
   - `Az.ConnectedMachine`
   - `Az.Security` (optional)

Wait for each module to finish importing before importing the next one.

### Via Azure CLI
```bash
# Note: Module import via CLI requires custom API calls
# It's recommended to use the Portal or PowerShell for module import
```

### Via PowerShell
```powershell
# Import Az.Accounts first
New-AzAutomationModule `
  -ResourceGroupName $rgName `
  -AutomationAccountName $aaName `
  -Name "Az.Accounts" `
  -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/Az.Accounts"

# Wait for Az.Accounts to finish (check in portal or wait ~5 minutes)
Start-Sleep -Seconds 300

# Import other modules
$modules = @("Az.Resources", "Az.ConnectedMachine", "Az.Security")
foreach ($module in $modules) {
    New-AzAutomationModule `
      -ResourceGroupName $rgName `
      -AutomationAccountName $aaName `
      -Name $module `
      -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$module"
    Start-Sleep -Seconds 60
}
```

## Step 4: Import the Runbook

### Via Azure Portal
1. Navigate to your Automation Account
2. Go to **Runbooks** > **+ Create a runbook**
3. Fill in the details:
   - **Name**: `Disable-DefenderOnTaggedArcMachines`
   - **Runbook type**: PowerShell
   - **Runtime version**: 7.2 (or latest)
   - **Description**: "Disables Defender on Arc machines tagged with DefenderForServers=Disabled"
4. Click **Create**
5. Paste the contents of `automation/Disable-DefenderOnTaggedArcMachines.ps1`
6. Click **Save**
7. Click **Publish**

### Via Azure CLI
```bash
az automation runbook create \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --name "Disable-DefenderOnTaggedArcMachines" \
  --type "PowerShell" \
  --description "Disables Defender on Arc machines tagged with DefenderForServers=Disabled"

# Import the runbook script
az automation runbook replace-content \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --name "Disable-DefenderOnTaggedArcMachines" \
  --content @automation/Disable-DefenderOnTaggedArcMachines.ps1

# Publish the runbook
az automation runbook publish \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --name "Disable-DefenderOnTaggedArcMachines"
```

### Via PowerShell
```powershell
Import-AzAutomationRunbook `
  -ResourceGroupName $rgName `
  -AutomationAccountName $aaName `
  -Name "Disable-DefenderOnTaggedArcMachines" `
  -Type PowerShell `
  -Path "automation/Disable-DefenderOnTaggedArcMachines.ps1" `
  -Published
```

## Step 5: Test the Runbook

Before scheduling, test the runbook:

### Via Azure Portal
1. Navigate to the runbook
2. Click **Start**
3. Add parameters (optional):
   - `WhatIf`: `True` (for dry-run)
   - `SubscriptionId`: Your subscription ID (optional)
   - `ResourceGroupName`: Specific RG to test (optional)
4. Click **OK**
5. Monitor the job output

### Via Azure CLI
```bash
az automation runbook start \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --name "Disable-DefenderOnTaggedArcMachines" \
  --parameters WhatIf=true
```

### Via PowerShell
```powershell
Start-AzAutomationRunbook `
  -ResourceGroupName $rgName `
  -AutomationAccountName $aaName `
  -Name "Disable-DefenderOnTaggedArcMachines" `
  -Parameters @{ WhatIf = $true }
```

## Step 6: Schedule the Runbook

Run the runbook on a regular schedule (e.g., daily):

### Via Azure Portal
1. Navigate to the runbook
2. Go to **Schedules** > **+ Add a schedule**
3. Create a new schedule:
   - **Name**: `Daily-Defender-Arc-Check`
   - **Starts**: Tomorrow at 2:00 AM (or your preferred time)
   - **Recurrence**: **Recurring** - Every 1 day
4. Configure parameters if needed
5. Click **Create**

### Via Azure CLI
```bash
# Create schedule
az automation schedule create \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --name "Daily-Defender-Arc-Check" \
  --frequency "Day" \
  --interval 1 \
  --start-time "2025-01-05T02:00:00+00:00"

# Link schedule to runbook
az automation job-schedule create \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --runbook-name "Disable-DefenderOnTaggedArcMachines" \
  --schedule-name "Daily-Defender-Arc-Check"
```

### Via PowerShell
```powershell
# Create schedule
$startTime = (Get-Date).AddDays(1).Date.AddHours(2)
New-AzAutomationSchedule `
  -ResourceGroupName $rgName `
  -AutomationAccountName $aaName `
  -Name "Daily-Defender-Arc-Check" `
  -StartTime $startTime `
  -DayInterval 1

# Link schedule to runbook
Register-AzAutomationScheduledRunbook `
  -ResourceGroupName $rgName `
  -AutomationAccountName $aaName `
  -RunbookName "Disable-DefenderOnTaggedArcMachines" `
  -ScheduleName "Daily-Defender-Arc-Check"
```

## Step 7: Monitor and Maintain

### View Runbook Jobs
```bash
# List recent jobs
az automation job list \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME

# Get specific job output
az automation job show \
  --automation-account-name $AA_NAME \
  --resource-group $RG_NAME \
  --job-id <job-id>
```

### Enable Diagnostic Logs (Optional)
Enable diagnostics to send runbook logs to Log Analytics:

1. Navigate to Automation Account > **Diagnostic settings**
2. Add diagnostic setting
3. Select **JobLogs** and **JobStreams**
4. Send to Log Analytics workspace

## Complete Solution Architecture

```
[Resource Group] --tag--> [Arc Machines]
        \                       |
         \--> [Policy 1]        | (TAG = DefenderForServers=Disabled)
                                |
                         [Policy 2: Audit]
                                |
                                v
                    [Azure Automation Runbook]
                                |
                                v
              [Remove Defender Extensions from Arc]
```

## Troubleshooting

### Runbook fails with authentication error
- Verify Managed Identity is enabled on the Automation Account
- Check RBAC role assignments for the Managed Identity

### Runbook doesn't find tagged machines
- Verify tags are correctly applied: `DefenderForServers=Disabled`
- Check the subscription context in the runbook job output

### Extension removal fails
- Verify "Azure Connected Machine Resource Administrator" role is assigned
- Check Arc machine connectivity status
- Review individual extension error messages in job output

### Modules fail to import
- Import modules in order: Az.Accounts first
- Wait for each module to complete before importing the next
- Use PowerShell 7.2 runtime for the runbook

## Cost Considerations

- **Automation Account**: Free tier includes 500 minutes/month of job runtime
- **Managed Identity**: No additional cost
- **Runbook execution**: Minimal cost for short-running jobs
- Typical monthly cost: < $5 USD for small environments

## Security Best Practices

1. Use Managed Identity instead of Run As accounts
2. Apply principle of least privilege for RBAC assignments
3. Enable diagnostic logging for audit trails
4. Regularly review runbook job outputs
5. Test changes in non-production environment first
6. Use Resource Locks on critical resources

## References

- [Azure Automation Documentation](https://docs.microsoft.com/azure/automation/)
- [Managed Identities](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Azure Arc Documentation](https://docs.microsoft.com/azure/azure-arc/)
- [Defender for Servers](https://docs.microsoft.com/azure/defender-for-cloud/defender-for-servers-introduction)
