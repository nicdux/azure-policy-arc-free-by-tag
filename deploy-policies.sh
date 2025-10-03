#!/bin/bash

# Azure Policy Deployment Script
# This script deploys the two custom policies for managing Defender for Servers on Arc machines

set -e

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
MANAGEMENT_GROUP=""
SCOPE=""

echo "=== Azure Policy Deployment for Arc Free by Tag ==="
echo ""
echo "Current subscription: $SUBSCRIPTION_ID"
echo ""
echo "Where do you want to deploy the policies?"
echo "1) Subscription (current)"
echo "2) Management Group"
read -p "Choose (1 or 2): " DEPLOY_CHOICE

if [ "$DEPLOY_CHOICE" == "2" ]; then
    read -p "Enter Management Group ID: " MANAGEMENT_GROUP
    SCOPE="/providers/Microsoft.Management/managementGroups/$MANAGEMENT_GROUP"
    SCOPE_TYPE="managementGroup"
else
    SCOPE="/subscriptions/$SUBSCRIPTION_ID"
    SCOPE_TYPE="subscription"
fi

echo ""
echo "Deploying to scope: $SCOPE"
echo ""

# Deploy Policy 1: Inherit Tag from Resource Group
echo "=== Deploying Policy 1: Inherit Tag from Resource Group ==="
POLICY1_NAME="inherit-defenderforservers-tag-from-rg"
POLICY1_DISPLAY_NAME="Inherit DefenderForServers tag from resource group"

if [ "$SCOPE_TYPE" == "managementGroup" ]; then
    az policy definition create \
        --name "$POLICY1_NAME" \
        --display-name "$POLICY1_DISPLAY_NAME" \
        --management-group "$MANAGEMENT_GROUP" \
        --rules policies/inherit-tag-from-rg.json \
        --mode Indexed
else
    az policy definition create \
        --name "$POLICY1_NAME" \
        --display-name "$POLICY1_DISPLAY_NAME" \
        --subscription "$SUBSCRIPTION_ID" \
        --rules policies/inherit-tag-from-rg.json \
        --mode Indexed
fi

echo "✓ Policy 1 deployed successfully"
echo ""

# Deploy Policy 2: Disable Defender for Servers on Arc by Tag
echo "=== Deploying Policy 2: Disable Defender for Servers on Arc by Tag ==="
POLICY2_NAME="disable-defender-arc-by-tag"
POLICY2_DISPLAY_NAME="Disable Defender for Servers on Arc machines with DefenderForServers=Disabled tag"

if [ "$SCOPE_TYPE" == "managementGroup" ]; then
    az policy definition create \
        --name "$POLICY2_NAME" \
        --display-name "$POLICY2_DISPLAY_NAME" \
        --management-group "$MANAGEMENT_GROUP" \
        --rules policies/disable-defender-arc-by-tag.json \
        --mode Indexed
else
    az policy definition create \
        --name "$POLICY2_NAME" \
        --display-name "$POLICY2_DISPLAY_NAME" \
        --subscription "$SUBSCRIPTION_ID" \
        --rules policies/disable-defender-arc-by-tag.json \
        --mode Indexed
fi

echo "✓ Policy 2 deployed successfully"
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "1. Assign Policy 1 ('$POLICY1_NAME') to your desired scope (subscription/resource group)"
echo "2. Assign Policy 2 ('$POLICY2_NAME') to your subscription"
echo "3. Enable remediation tasks for both policies to apply them to existing resources"
echo "4. Add the tag 'DefenderForServers=Disabled' to resource groups containing Arc machines you want on Free tier"
echo ""
echo "Example assignment commands:"
echo "  az policy assignment create --name 'assign-inherit-tag' --policy '$POLICY1_NAME' --scope '$SCOPE'"
echo "  az policy assignment create --name 'assign-disable-defender-arc' --policy '$POLICY2_NAME' --scope '$SCOPE' --location <region> --assign-identity"
echo ""
