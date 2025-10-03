# Quick Start Guide

Este guia fornece os passos mínimos para implementar a solução completa.

## Resumo da Solução

**Objetivo**: Manter VMs do Azure com Defender for Servers P2 e colocar servidores Azure Arc em Free/sem plano automaticamente usando tags e Azure Policy.

**Componentes**:
1. 2 Azure Policies (definições customizadas)
2. 1 Azure Automation Runbook
3. Tags em Resource Groups

## Implementação em 5 Minutos

### Passo 1: Deploy das Políticas (2 min)

```bash
# Clone o repositório
git clone https://github.com/nicdux/azure-policy-arc-free-by-tag.git
cd azure-policy-arc-free-by-tag

# Login no Azure
az login

# Deploy das políticas
./deploy-policies.sh
```

Ou use PowerShell:
```powershell
./deploy-policies.ps1
```

### Passo 2: Atribuir as Políticas (1 min)

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LOCATION="westeurope"

# Atribuir Policy 1 (herança de tag)
az policy assignment create \
  --name "inherit-defenderforservers-tag" \
  --policy "inherit-defenderforservers-tag-from-rg" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --location "$LOCATION" \
  --assign-identity

# Atribuir Policy 2 (audit)
az policy assignment create \
  --name "audit-defender-arc-tag" \
  --policy "disable-defender-arc-by-tag" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Passo 3: Aplicar Tags nos Resource Groups (1 min)

```bash
# Aplique em cada RG que contém Arc servers que devem ficar em Free
az group update --name "rg-arc-servers-dev" --tags DefenderForServers=Disabled
az group update --name "rg-arc-servers-test" --tags DefenderForServers=Disabled
```

### Passo 4: Remediar Recursos Existentes (1 min)

```bash
# Force a herança da tag para recursos existentes
az policy remediation create \
  --name "remediate-$(date +%s)" \
  --policy-assignment "inherit-defenderforservers-tag"
```

### Passo 5: Configurar Automation (Opcional mas Recomendado)

Para automação completa, configure o Azure Automation runbook:

**Guia Detalhado**: [`automation/AUTOMATION-SETUP.md`](automation/AUTOMATION-SETUP.md)

**Resumo Rápido**:
```bash
# 1. Criar Automation Account
az automation account create \
  --name "aa-defender-arc" \
  --resource-group "rg-defender-automation" \
  --location "westeurope" \
  --assign-identity

# 2. Atribuir permissões (substitua IDENTITY_ID)
IDENTITY_ID=$(az automation account show --name "aa-defender-arc" --resource-group "rg-defender-automation" --query identity.principalId -o tsv)

az role assignment create --assignee $IDENTITY_ID --role "Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee $IDENTITY_ID --role "Azure Connected Machine Resource Administrator" --scope "/subscriptions/$SUBSCRIPTION_ID"

# 3. Importar runbook (via Portal é mais fácil - veja automation/AUTOMATION-SETUP.md)
```

## Verificação

### Verificar Conformidade das Políticas
```bash
az policy state list --filter "complianceState eq 'NonCompliant'" --output table
```

### Verificar Tags nos Recursos
```bash
# Listar Arc machines com a tag
az resource list --resource-type "Microsoft.HybridCompute/machines" --query "[?tags.DefenderForServers=='Disabled'].{Name:name, RG:resourceGroup, Tags:tags}" --output table
```

### Verificar Jobs do Runbook (se configurado)
```bash
az automation job list \
  --automation-account-name "aa-defender-arc" \
  --resource-group "rg-defender-automation" \
  --output table
```

## Estrutura de Tags

| Resource Group | Tag | Arc Machines | Azure VMs |
|----------------|-----|--------------|-----------|
| rg-prod | *sem tag* | Defender P2 ✓ | Defender P2 ✓ |
| rg-dev | DefenderForServers=Disabled | Free ✓ | Defender P2 ✓ |
| rg-test | DefenderForServers=Disabled | Free ✓ | Defender P2 ✓ |

## Fluxo Completo

```
1. Admin adiciona tag no RG
          ↓
2. Policy herda tag para recursos
          ↓
3. Policy audit identifica Arc machines
          ↓
4. Runbook remove extensões Defender
          ↓
5. Arc machine fica em Free
```

## Comandos Úteis

### Listar todas as políticas atribuídas
```bash
az policy assignment list --output table
```

### Remover uma política
```bash
az policy assignment delete --name "inherit-defenderforservers-tag"
```

### Ver detalhes de uma remediação
```bash
az policy remediation show --name "remediate-<id>" --policy-assignment "inherit-defenderforservers-tag"
```

### Executar runbook manualmente
```bash
az automation runbook start \
  --automation-account-name "aa-defender-arc" \
  --resource-group "rg-defender-automation" \
  --name "Disable-DefenderOnTaggedArcMachines" \
  --parameters WhatIf=true
```

## Próximos Passos

1. ✅ Implementar as políticas (este guia)
2. ✅ Testar em um RG pequeno primeiro
3. ✅ Configurar o Automation runbook
4. ✅ Expandir para outros RGs conforme necessário
5. ✅ Monitorar conformidade regularmente

## Suporte

- **Issues**: https://github.com/nicdux/azure-policy-arc-free-by-tag/issues
- **Documentação Completa**: [README.md](README.md)
- **Setup Automation**: [automation/AUTOMATION-SETUP.md](automation/AUTOMATION-SETUP.md)
- **Exemplos**: [ASSIGNMENT-EXAMPLES.md](ASSIGNMENT-EXAMPLES.md)

## Rollback

Para reverter a solução:

```bash
# 1. Remover atribuições de política
az policy assignment delete --name "inherit-defenderforservers-tag"
az policy assignment delete --name "audit-defender-arc-tag"

# 2. Remover as definições
az policy definition delete --name "inherit-defenderforservers-tag-from-rg"
az policy definition delete --name "disable-defender-arc-by-tag"

# 3. Remover tags dos RGs
az group update --name "rg-arc-servers-dev" --remove tags.DefenderForServers

# 4. Deletar Automation Account (se criado)
az automation account delete --name "aa-defender-arc" --resource-group "rg-defender-automation" --yes
```
