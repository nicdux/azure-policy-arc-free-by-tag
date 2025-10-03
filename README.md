# azure-policy-arc-free-by-tag

Resumo executivo Objetivo: manter VMs do Azure com Defender for Servers Plan 2 (P2) e colocar servidores Azure Arc em Free/sem plano, de forma automática, usando TAG + Azure Policy (com remediação).

## 📋 Visão Geral

Este repositório contém Azure Policies customizadas para gerenciar automaticamente o Microsoft Defender for Servers em ambientes híbridos, permitindo que:

- **VMs do Azure**: Permaneçam com Defender for Servers Plan 2 (P2) ativo
- **Servidores Azure Arc**: Sejam colocados em Free/sem plano automaticamente, baseado em tags

## 🎯 Arquitetura da Solução

```
[Resource Group Arc] --tag--> [Recursos (Arc/VM/VMSS)]
      \                                  |
       \--> [Policy 1: Herdar TAG]       |  (TAG = DefenderForServers=Disabled)
                                         v
                              [Policy 2: Audit por TAG]
                                         |
                                         v
                              [Azure Automation Runbook]
                                         |
                                         v
                   [Arc = Free/sem Defender]   [Azure VMs = P2 na assinatura]
```

A solução completa consiste em:

1. **Tag no Resource Group**: Define `DefenderForServers=Disabled` nos RGs com Arc servers
2. **Policy 1**: Herda automaticamente a tag para os recursos
3. **Policy 2**: Identifica Arc machines com a tag (efeito audit)
4. **Automation Runbook**: Remove extensões do Defender dos Arc machines identificados
5. **Resultado**: Arc machines ficam sem Defender (Free), Azure VMs mantêm P2

## 📦 Componentes

### Policy 1: Herdar Tag do Resource Group
**Arquivo**: `policies/inherit-tag-from-rg.json`

Esta política herda automaticamente a tag `DefenderForServers` do Resource Group para os recursos:
- Virtual Machines (Azure VMs)
- Virtual Machine Scale Sets (VMSS)
- Azure Arc Machines

**Efeito**: `modify` (com remediação automática)

### Policy 2: Audit Arc Machines com Tag de Exclusão
**Arquivo**: `policies/disable-defender-arc-by-tag.json`

Esta política identifica máquinas Azure Arc com a tag `DefenderForServers=Disabled` e marca-as para auditoria.

**Efeito**: `audit` (identifica recursos que precisam de ação)

### Azure Automation Runbook
**Arquivo**: `automation/Disable-DefenderOnTaggedArcMachines.ps1`

Runbook que automaticamente remove extensões do Microsoft Defender for Servers de máquinas Arc identificadas pelas políticas. O runbook:
- Busca Arc machines com tag `DefenderForServers=Disabled`
- Remove extensões do Defender (MDE, MMA, AMA)
- Executa periodicamente via schedule

**Guia de Setup**: Veja `automation/AUTOMATION-SETUP.md` para instruções detalhadas

## 🚀 Implantação

### Pré-requisitos

- Azure CLI instalado ([Instruções](https://docs.microsoft.com/cli/azure/install-azure-cli))
  OU
- Azure PowerShell instalado ([Instruções](https://docs.microsoft.com/powershell/azure/install-az-ps))
- Permissões adequadas na subscrição ou Management Group:
  - `Resource Policy Contributor` para criar definições de política
  - `User Access Administrator` ou `Owner` para criar atribuições com identidade gerenciada

### Opção 1: Deploy via Bash Script

```bash
# Clone o repositório
git clone https://github.com/nicdux/azure-policy-arc-free-by-tag.git
cd azure-policy-arc-free-by-tag

# Login no Azure
az login

# Executar script de deploy
./deploy-policies.sh
```

### Opção 2: Deploy via PowerShell

```powershell
# Clone o repositório
git clone https://github.com/nicdux/azure-policy-arc-free-by-tag.git
cd azure-policy-arc-free-by-tag

# Login no Azure
Connect-AzAccount

# Executar script de deploy
./deploy-policies.ps1

# Ou especificar uma subscription
./deploy-policies.ps1 -SubscriptionId "your-subscription-id"

# Ou usar Management Group
./deploy-policies.ps1 -ManagementGroupId "your-mg-id" -UseManagementGroup
```

### Opção 3: Deploy Manual via Azure CLI

```bash
# Policy 1: Herdar Tag
az policy definition create \
  --name "inherit-defenderforservers-tag-from-rg" \
  --display-name "Inherit DefenderForServers tag from resource group" \
  --rules policies/inherit-tag-from-rg.json \
  --mode Indexed

# Policy 2: Disable Defender por Tag
az policy definition create \
  --name "disable-defender-arc-by-tag" \
  --display-name "Disable Defender for Servers on Arc machines with DefenderForServers=Disabled tag" \
  --rules policies/disable-defender-arc-by-tag.json \
  --mode Indexed
```

## 📝 Configuração e Uso

### Passo 1: Atribuir as Políticas

Após criar as definições de política, você precisa atribuí-las:

#### Atribuir Policy 1 (Herdar Tag)
```bash
# Atribuir ao nível da subscription
az policy assignment create \
  --name "assign-inherit-defenderforservers-tag" \
  --policy "inherit-defenderforservers-tag-from-rg" \
  --scope "/subscriptions/<subscription-id>" \
  --location "<region>" \
  --assign-identity

# Ou atribuir a um Resource Group específico
az policy assignment create \
  --name "assign-inherit-defenderforservers-tag" \
  --policy "inherit-defenderforservers-tag-from-rg" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/<rg-name>" \
  --location "<region>" \
  --assign-identity
```

#### Atribuir Policy 2 (Audit Defender)
```bash
# Atribuir ao nível da subscription
az policy assignment create \
  --name "assign-audit-defender-arc" \
  --policy "disable-defender-arc-by-tag" \
  --scope "/subscriptions/<subscription-id>"
```

### Passo 2: Aplicar a Tag no Resource Group

Adicione a tag `DefenderForServers=Disabled` aos Resource Groups que contêm servidores Arc que você quer em Free tier:

```bash
az group update \
  --name "<resource-group-name>" \
  --tags DefenderForServers=Disabled
```

### Passo 3: Executar Remediação (para recursos existentes)

Para aplicar a Policy 1 a recursos existentes, crie tarefas de remediação:

```bash
# Remediar Policy 1 (Herdar Tag)
az policy remediation create \
  --name "remediate-inherit-tag" \
  --policy-assignment "assign-inherit-defenderforservers-tag" \
  --resource-group "<resource-group-name>"
```

### Passo 4: Configurar Azure Automation

Para automatizar a remoção do Defender dos Arc machines:

1. Siga o guia detalhado em [`automation/AUTOMATION-SETUP.md`](automation/AUTOMATION-SETUP.md)
2. Crie uma Automation Account com Managed Identity
3. Importe o runbook `Disable-DefenderOnTaggedArcMachines.ps1`
4. Configure um schedule para execução periódica (ex: diária)

**Resumo rápido**:
```bash
# Criar Automation Account
az automation account create \
  --name "aa-defender-arc-automation" \
  --resource-group "<rg-name>" \
  --location "<region>" \
  --assign-identity

# Atribuir permissões à Managed Identity
# Ver automation/AUTOMATION-SETUP.md para detalhes
```

## 🔍 Verificação

Para verificar se as políticas estão funcionando:

```bash
# Ver todas as atribuições de política
az policy assignment list --output table

# Ver recursos não conformes
az policy state list \
  --filter "complianceState eq 'NonCompliant'" \
  --output table

# Ver status de remediação
az policy remediation show \
  --name "remediate-inherit-tag" \
  --policy-assignment "assign-inherit-defenderforservers-tag"
```

## 🎯 Casos de Uso

### Cenário 1: Arc Servers em Free, VMs em P2
1. Implante as políticas ao nível da subscription
2. Configure o Azure Automation runbook (veja `automation/AUTOMATION-SETUP.md`)
3. Adicione a tag `DefenderForServers=Disabled` aos RGs com Arc servers
4. A Policy 1 herda a tag para os Arc servers
5. A Policy 2 identifica os Arc servers taggeados
6. O Automation runbook remove as extensões do Defender
7. Azure VMs sem a tag permanecem em P2

### Cenário 2: Controle Granular por Resource Group
1. Organize seus Arc servers em RGs separados por ambiente (prod, dev, test)
2. Adicione a tag `DefenderForServers=Disabled` apenas aos RGs de dev/test
3. Arc servers em prod mantêm P2, dev/test ficam em Free
4. O runbook processa apenas os Arc servers taggeados

### Cenário 3: Migração Gradual
1. Comece com a Policy 1 apenas, para herdar tags
2. Monitore quais recursos receberam a tag
3. Ative a Policy 2 para auditoria
4. Configure o Automation runbook quando estiver pronto
5. Teste com um RG pequeno primeiro (use parâmetro ResourceGroupName no runbook)

## ⚠️ Considerações Importantes

1. **Permissions**: 
   - As políticas com efeito `modify` requerem identidade gerenciada com permissões adequadas
   - O Automation runbook requer Managed Identity com roles específicas (veja `automation/AUTOMATION-SETUP.md`)

2. **Escopo**: 
   - Policy 1 opera no nível de recurso
   - Policy 2 identifica recursos para auditoria
   - O Automation runbook opera no nível de subscription ou RG

3. **Timing**: 
   - Herança de tags é imediata com remediação
   - Remoção de extensões depende do schedule do runbook (recomendado: execução diária)
   - Extensões podem levar alguns minutos para serem completamente removidas

4. **Azure VMs**: 
   - As políticas são projetadas para **não afetar** VMs do Azure
   - Apenas Arc machines (Microsoft.HybridCompute/machines) são processadas

5. **Compliance**: 
   - Monitore o estado de conformidade das políticas no Azure Policy dashboard
   - Revise os logs do Automation runbook regularmente
   - Use o parâmetro `WhatIf` do runbook para testes

6. **Reversão**:
   - Para reativar Defender em um Arc machine, remova a tag `DefenderForServers=Disabled`
   - Reinstale as extensões do Defender manualmente ou via política

## 🔧 Troubleshooting

### Política não está sendo aplicada
- Verifique se a política está atribuída ao escopo correto
- Confirme que a identidade gerenciada tem as permissões necessárias
- Revise os logs de atividade do Azure para erros de deployment

### Tag não está sendo herdada
- Certifique-se que a tag existe no Resource Group
- Verifique se o recurso é do tipo suportado (VM/VMSS/Arc)
- Execute uma tarefa de remediação para recursos existentes

### Defender não está sendo removido dos Arc machines
- Verifique se o Automation runbook está configurado e agendado
- Confirme que a Managed Identity do Automation Account tem as permissões necessárias
- Revise os logs do runbook job para erros específicos
- Verifique se a tag `DefenderForServers=Disabled` está presente no Arc machine
- Use o parâmetro `WhatIf=true` para testar sem fazer mudanças

### Runbook não encontra Arc machines
- Verifique o valor exato da tag: `DefenderForServers=Disabled` (case sensitive)
- Confirme que o runbook está executando no subscription correto
- Revise os logs do job para mensagens de erro

### Extensões não são removidas
- Verifique se a Managed Identity tem role "Azure Connected Machine Resource Administrator"
- Confirme que o Arc machine está conectado (status online)
- Algumas extensões podem estar protegidas - remova manualmente se necessário

## 📚 Referências

- [Azure Policy Documentation](https://docs.microsoft.com/azure/governance/policy/)
- [Microsoft Defender for Servers](https://docs.microsoft.com/azure/defender-for-cloud/defender-for-servers-introduction)
- [Azure Arc Documentation](https://docs.microsoft.com/azure/azure-arc/)
- [Azure Policy Effects](https://docs.microsoft.com/azure/governance/policy/concepts/effects)

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo LICENSE para mais detalhes.

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor, abra uma issue ou pull request para sugestões e melhorias.
