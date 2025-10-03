#!/bin/bash
# Validation script for Azure Policy definitions

echo "=== Azure Policy Definition Validator ==="
echo ""

ERRORS=0

# Function to validate JSON
validate_json() {
    local file=$1
    local name=$2
    
    echo -n "Validating $name... "
    if python3 -m json.tool "$file" > /dev/null 2>&1; then
        echo "✓ Valid JSON"
    else
        echo "✗ Invalid JSON"
        ERRORS=$((ERRORS + 1))
    fi
}

# Function to check required fields
check_policy_fields() {
    local file=$1
    local name=$2
    
    echo -n "Checking required fields in $name... "
    
    if ! python3 -c "
import json
import sys

with open('$file', 'r') as f:
    policy = json.load(f)

required_fields = ['mode', 'policyRule', 'metadata']
missing = [f for f in required_fields if f not in policy]

if missing:
    print('Missing fields:', ', '.join(missing))
    sys.exit(1)

if 'if' not in policy['policyRule'] or 'then' not in policy['policyRule']:
    print('policyRule must have if and then')
    sys.exit(1)

if 'effect' not in policy['policyRule']['then']:
    print('policyRule.then must have effect')
    sys.exit(1)

print('OK')
" 2>&1; then
        ERRORS=$((ERRORS + 1))
        echo "✗ Failed"
    else
        echo "✓ Passed"
    fi
}

# Validate Policy 1
echo "--- Policy 1: Inherit Tag from Resource Group ---"
if [ -f "policies/inherit-tag-from-rg.json" ]; then
    validate_json "policies/inherit-tag-from-rg.json" "Policy 1"
    check_policy_fields "policies/inherit-tag-from-rg.json" "Policy 1"
else
    echo "✗ File not found: policies/inherit-tag-from-rg.json"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Validate Policy 2
echo "--- Policy 2: Audit Defender Arc by Tag ---"
if [ -f "policies/disable-defender-arc-by-tag.json" ]; then
    validate_json "policies/disable-defender-arc-by-tag.json" "Policy 2"
    check_policy_fields "policies/disable-defender-arc-by-tag.json" "Policy 2"
else
    echo "✗ File not found: policies/disable-defender-arc-by-tag.json"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Check deployment scripts
echo "--- Deployment Scripts ---"
if [ -f "deploy-policies.sh" ]; then
    echo "✓ deploy-policies.sh exists"
else
    echo "✗ deploy-policies.sh not found"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "deploy-policies.ps1" ]; then
    echo "✓ deploy-policies.ps1 exists"
else
    echo "✗ deploy-policies.ps1 not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Check automation files
echo "--- Automation Files ---"
if [ -f "automation/Disable-DefenderOnTaggedArcMachines.ps1" ]; then
    echo "✓ Runbook script exists"
else
    echo "✗ Runbook script not found"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "automation/AUTOMATION-SETUP.md" ]; then
    echo "✓ Automation setup guide exists"
else
    echo "✗ Automation setup guide not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "==================================="
if [ $ERRORS -eq 0 ]; then
    echo "✓ All validations passed!"
    exit 0
else
    echo "✗ $ERRORS error(s) found"
    exit 1
fi
