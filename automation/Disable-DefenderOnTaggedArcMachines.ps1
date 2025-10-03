<#
.SYNOPSIS
    Azure Automation Runbook to disable Defender for Servers on Arc machines with specific tag

.DESCRIPTION
    This runbook scans for Azure Arc machines tagged with 'DefenderForServers=Disabled'
    and removes/disables the Microsoft Defender for Endpoint and monitoring agents.
    
    Should be scheduled to run periodically (e.g., daily) or triggered by Azure Policy compliance events.

.NOTES
    Author: Azure Policy Arc Free by Tag Solution
    Version: 1.0
    
.REQUIREMENTS
    - Azure Automation Account with System-assigned Managed Identity
    - Managed Identity requires:
      - Reader on subscription (to query Arc machines)
      - Hybrid Compute Contributor on Arc machines (to manage extensions)
      - Security Admin (to modify Defender settings)
    - Az.Accounts, Az.ConnectedMachine, Az.Security modules
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# Import required modules
Import-Module Az.Accounts
Import-Module Az.ConnectedMachine
Import-Module Az.Resources

try {
    # Connect using System-assigned Managed Identity
    Write-Output "Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity | Out-Null
    
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        Write-Output "Using subscription: $SubscriptionId"
    } else {
        $context = Get-AzContext
        Write-Output "Using default subscription: $($context.Subscription.Name)"
    }
    
    # Build resource group filter
    $rgFilter = if ($ResourceGroupName) {
        Write-Output "Filtering by Resource Group: $ResourceGroupName"
        $ResourceGroupName
    } else {
        Write-Output "Scanning all Resource Groups"
        $null
    }
    
    # Query Arc machines with the DisablDefender tag
    Write-Output "`nQuerying Azure Arc machines with tag 'DefenderForServers=Disabled'..."
    
    if ($rgFilter) {
        $arcMachines = Get-AzConnectedMachine -ResourceGroupName $rgFilter | 
            Where-Object { $_.Tag['DefenderForServers'] -eq 'Disabled' }
    } else {
        # Get all Arc machines across subscription
        $allResourceGroups = Get-AzResourceGroup
        $arcMachines = @()
        foreach ($rg in $allResourceGroups) {
            $machines = Get-AzConnectedMachine -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue |
                Where-Object { $_.Tag['DefenderForServers'] -eq 'Disabled' }
            if ($machines) {
                $arcMachines += $machines
            }
        }
    }
    
    if ($arcMachines.Count -eq 0) {
        Write-Output "No Arc machines found with tag 'DefenderForServers=Disabled'"
        return
    }
    
    Write-Output "Found $($arcMachines.Count) Arc machine(s) tagged for Defender exclusion:"
    foreach ($machine in $arcMachines) {
        Write-Output "  - $($machine.Name) in $($machine.ResourceGroupName)"
    }
    
    # Process each Arc machine
    $processedCount = 0
    $skippedCount = 0
    $errorCount = 0
    
    foreach ($machine in $arcMachines) {
        Write-Output "`nProcessing: $($machine.Name)"
        
        try {
            # Get extensions on the Arc machine
            $extensions = Get-AzConnectedMachineExtension -MachineName $machine.Name -ResourceGroupName $machine.ResourceGroupName
            
            # List of Defender-related extensions to remove
            $defenderExtensions = $extensions | Where-Object {
                $_.ExtensionType -in @(
                    'MDE.Linux',
                    'MDE.Windows', 
                    'MicrosoftMonitoringAgent',
                    'OmsAgentForLinux',
                    'AzureMonitorLinuxAgent',
                    'AzureMonitorWindowsAgent'
                ) -or
                $_.Name -like '*Defender*' -or
                $_.Name -like '*MDE*'
            }
            
            if ($defenderExtensions.Count -eq 0) {
                Write-Output "  No Defender extensions found on this machine"
                $skippedCount++
                continue
            }
            
            Write-Output "  Found $($defenderExtensions.Count) Defender-related extension(s):"
            foreach ($ext in $defenderExtensions) {
                Write-Output "    - $($ext.Name) ($($ext.ExtensionType))"
            }
            
            if ($WhatIf) {
                Write-Output "  [WHATIF] Would remove these extensions"
                $processedCount++
            } else {
                # Remove each Defender extension
                foreach ($ext in $defenderExtensions) {
                    Write-Output "  Removing extension: $($ext.Name)..."
                    Remove-AzConnectedMachineExtension `
                        -MachineName $machine.Name `
                        -ResourceGroupName $machine.ResourceGroupName `
                        -Name $ext.Name `
                        -NoWait `
                        -Force | Out-Null
                    Write-Output "    ✓ Removal initiated"
                }
                $processedCount++
            }
            
        } catch {
            Write-Error "  Error processing $($machine.Name): $_"
            $errorCount++
        }
    }
    
    # Summary
    Write-Output "`n========================================="
    Write-Output "Summary:"
    Write-Output "  Total machines found: $($arcMachines.Count)"
    Write-Output "  Processed: $processedCount"
    Write-Output "  Skipped (no extensions): $skippedCount"
    Write-Output "  Errors: $errorCount"
    Write-Output "========================================="
    
    if ($WhatIf) {
        Write-Output "`nWhatIf mode - no changes were made"
    }
    
} catch {
    Write-Error "Fatal error: $_"
    throw
}
