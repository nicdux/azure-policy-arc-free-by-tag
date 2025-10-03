# Example Assignment Configuration

## Policy 1: Inherit DefenderForServers Tag from Resource Group

### Assignment Details
- **Name**: assign-inherit-defenderforservers-tag
- **Display Name**: Inherit DefenderForServers tag from resource group to resources
- **Scope**: /subscriptions/{subscription-id} or /subscriptions/{subscription-id}/resourceGroups/{rg-name}
- **Effect**: modify
- **Requires Identity**: Yes
- **Location for Identity**: Same as resources being managed

### Parameters
```json
{
  "tagName": {
    "value": "DefenderForServers"
  }
}
```

### Role Assignments Required
- Contributor (for the managed identity)

---

## Policy 2: Disable Defender for Servers on Arc by Tag

### Assignment Details
- **Name**: assign-disable-defender-arc
- **Display Name**: Disable Defender for Servers on Arc machines with DefenderForServers=Disabled tag
- **Scope**: /subscriptions/{subscription-id}
- **Effect**: deployIfNotExists
- **Requires Identity**: Yes
- **Location for Identity**: westeurope (or your preferred region)

### Parameters
No parameters required (uses default tag check)

### Role Assignments Required
- Security Admin (for the managed identity)

---

## Resource Group Tagging

Add the following tag to Resource Groups containing Arc servers that should be on Free tier:

```bash
DefenderForServers=Disabled
```

### Azure CLI Example
```bash
az group update --name "rg-arc-servers-dev" --tags DefenderForServers=Disabled
```

### PowerShell Example
```powershell
Set-AzResourceGroup -Name "rg-arc-servers-dev" -Tag @{DefenderForServers="Disabled"}
```

### Azure Portal
1. Navigate to the Resource Group
2. Go to "Tags" in the left menu
3. Add tag: Name=`DefenderForServers`, Value=`Disabled`
4. Click "Apply"

---

## Remediation Tasks

To apply policies to existing resources, create remediation tasks:

### Azure CLI
```bash
# Remediate Policy 1
az policy remediation create \
  --name "remediate-inherit-tag-$(date +%Y%m%d-%H%M%S)" \
  --policy-assignment "assign-inherit-defenderforservers-tag" \
  --resource-group "<resource-group-name>"

# Remediate Policy 2
az policy remediation create \
  --name "remediate-disable-defender-$(date +%Y%m%d-%H%M%S)" \
  --policy-assignment "assign-disable-defender-arc"
```

### PowerShell
```powershell
# Remediate Policy 1
Start-AzPolicyRemediation `
  -Name "remediate-inherit-tag-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  -PolicyAssignmentId "/subscriptions/{subscription-id}/providers/Microsoft.Authorization/policyAssignments/assign-inherit-defenderforservers-tag" `
  -ResourceGroupName "<resource-group-name>"

# Remediate Policy 2
Start-AzPolicyRemediation `
  -Name "remediate-disable-defender-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  -PolicyAssignmentId "/subscriptions/{subscription-id}/providers/Microsoft.Authorization/policyAssignments/assign-disable-defender-arc"
```
