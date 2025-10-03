# Azure Policy — Arc Free por Tag (Zero ➜ Hero)
**Repo:** `azure-policy-arc-free-by-tag`  
**Policy (display name):** `Disable Defender for Servers (resource-level) by Tag + RG Tag Inheritance`

**Resumo executivo**  
Objetivo: manter **VMs do Azure** com **Defender for Servers Plan 2 (P2)** e colocar **servidores Azure Arc** em **Free/sem plano**, de forma **automática**, usando **TAG** + **Azure Policy** (com remediação).



---

## 1) Contexto e motivação

- **Problema**: assinatura com **P2** habilitado (para **Azure VMs**), mas o cliente **não quer pagar** esse plano para **servidores Azure Arc**.
- **Solução**: usar **TAG** e **Azure Policy** para **herdar** a TAG no RG dos Arc e **desabilitar o plano** no **nível do recurso** quando a TAG estiver presente.
- **Critérios de sucesso**:
  - VMs do Azure seguem **P2** normalmente.
  - Servidores **Azure Arc** no RG de controle ficam **Free/sem plano** (sem cobrança).
  - **Sem** extensão **MDE** nos Arc (se essa for a decisão) e, se houve histórico, **offboarding** executado.

---

## 2) Arquitetura e decisões

- **mode**: `Indexed` (avalia recursos ARM individuais — VMs, VMSS, Arc Machines).
- **effect**:
  - **Policy 1 (TAG inherit)**: `Modify` (grava TAG automaticamente + Remediation).
  - **Policy 2 (Disable por TAG)**: `DeployIfNotExists`/`Modify` (conforme built-in usada; controla a cobertura no *resource-level*).
- **Escopos suportados**: RG (recomendado), Subscription e MG.
- **Trade-offs**:
  - Algumas built-ins checam `pricingTier` **na assinatura** e podem mostrar **Non-compliant** mesmo com Arc=Free. O efeito (billing) permanece. Para “verde”, usar **Manage/Customize coverage** por TAG ou **Policy Exemptions**.

---

## 3) Estrutura de pastas

```text
.
├── policy/
│   ├── definition.json
│   └── parameters.example.json
├── assignment/
│   └── assignment.parameters.example.json
├── scripts/
│   ├── deploy-azcli.sh
│   └── deploy-pwsh.ps1
└── README.md

Nota: abaixo há uma Initiative (policySetDefinition) que referencia duas built-ins e parametriza a TAG. Substitua os IDs das built-ins pelos IDs do seu tenant (veja “TODO” no final).

4) Código — Initiative (policy set) + parâmetros
policy/definition.json

{
  "properties": {
    "displayName": "Arc em Free por TAG (Disable Defender for Servers no recurso + TAG do RG)",
    "description": "Mantém Azure VMs em P2 na assinatura e coloca Arc (e demais recursos marcados) em Free/sem plano via TAG herdada do RG.",
    "metadata": {
      "category": "Security Center",
      "version": "1.0.0",
      "owner": "SecOps/Cloud",
      "zrh:notes": "Initiative que encapsula: TAG inherit (Modify) e Disable Defender for Servers by TAG (resource-level)."
    },
    "policyType": "Custom",
    "parameters": {
      "tagName": {
        "type": "String",
        "metadata": {
          "displayName": "TAG (key)",
          "description": "Nome da TAG usada para controle."
        },
        "defaultValue": "DefenderForServers"
      },
      "tagValues": {
        "type": "Array",
        "metadata": {
          "displayName": "TAG (values)",
          "description": "Valores da TAG que ativam o 'disable' no resource-level."
        },
        "defaultValue": [
          "Disabled"
        ]
      }
    },
    "policyDefinitions": [
      {
        "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/<ID_BUILTIN_INHERIT_TAG>",
        "policyDefinitionReferenceId": "inherit-tag-from-rg",
        "parameters": {
          "tagName": {
            "value": "[parameters('tagName')]"
          }
        }
      },
      {
        "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/<ID_BUILTIN_DISABLE_DEFENDER_BY_TAG>",
        "policyDefinitionReferenceId": "disable-defender-by-tag",
        "parameters": {
          "inclusionTagName": {
            "value": "[parameters('tagName')]"
          },
          "inclusionTagValues": {
            "value": "[parameters('tagValues')]"
          }
        }
      }
    ]
  }
}


policy/parameters.example.json

{
  "parameters": {
    "tagName": {
      "value": "DefenderForServers"
    },
    "tagValues": {
      "value": [
        "Disabled"
      ]
    }
  }
}

5) Assignment (exemplo: escopo = Resource Group)
{
  "identity": {
    "type": "SystemAssigned"
  },
  "location": "eastus",
  "properties": {
    "displayName": "RG-ARC | Arc em Free por TAG (Disable + Inherit)",
    "description": "Mantém Arc em Free/sem plano por TAG, herdada do RG.",
    "enforcementMode": "Default",
    "parameters": {
      "tagName": {
        "value": "DefenderForServers"
      },
      "tagValues": {
        "value": [ "Disabled" ]
      }
    },
    "policyDefinitionId": "/subscriptions/<SUBSCRIPTION_ID>/providers/Microsoft.Authorization/policySetDefinitions/<POLICY_SET_ID>"
  }
}

Escopo: RG onde os Arc serão conectados (ex.: rg-azurearc-itsbx-us).
A Managed Identity criada pela assignment precisa de permissão (ex.: Contributor/Tag Contributor) para a remediation.


6) Scripts de deploy
scripts/deploy-azcli.sh

#!/usr/bin/env bash
set -euo pipefail

SUBS="<SUBSCRIPTION_ID>"
RG="<RG_ARC>"              # ex.: rg-azurearc-itsbx-us
LOC="eastus"

# 0) (opcional) criar RG
# az group create -n "$RG" -l "$LOC"

# 1) importar/atualizar a policy set (initiative)
POLICY_SET_NAME="arc-free-by-tag"
az policy set-definition create \
  --name "$POLICY_SET_NAME" \
  --subscription "$SUBS" \
  --definitions @policy/definition.json \
  --params @policy/parameters.example.json

# obter ID da policy set
POLICY_SET_ID=$(az policy set-definition show --name "$POLICY_SET_NAME" --subscription "$SUBS" --query "id" -o tsv)

# 2) assignment no escopo do RG
ASSIGN_NAME="rg-arc-free-by-tag"
az policy assignment create \
  --name "$ASSIGN_NAME" \
  --display-name "RG-ARC | Arc em Free por TAG (Disable + Inherit)" \
  --scope "/subscriptions/$SUBS/resourceGroups/$RG" \
  --policy-set-definition "$POLICY_SET_ID" \
  --location "$LOC" \
  --identity-type SystemAssigned \
  --params @policy/parameters.example.json

# 3) remediation: herança de TAG (para recursos existentes)
az policy remediation create \
  --name "remediate-inherit-tag" \
  --policy-assignment "/subscriptions/$SUBS/resourceGroups/$RG/providers/Microsoft.Authorization/policyAssignments/$ASSIGN_NAME" \
  --resource-discovery-mode ReEvaluateCompliance \
  --location-filter "$LOC"

# 4) remediation: disable por TAG (para recursos existentes)
az policy remediation create \
  --name "remediate-disable-by-tag" \
  --policy-assignment "/subscriptions/$SUBS/resourceGroups/$RG/providers/Microsoft.Authorization/policyAssignments/$ASSIGN_NAME" \
  --resource-discovery-mode ReEvaluateCompliance \
  --location-filter "$LOC"

echo "OK. Assignment + remediations criadas."

scripts/deploy-pwsh.ps1

param(
  [string]$SubscriptionId = "<SUBSCRIPTION_ID>",
  [string]$ResourceGroup  = "<RG_ARC>", # ex.: rg-azurearc-itsbx-us
  [string]$Location       = "eastus"
)

$ErrorActionPreference = "Stop"
$polSetName = "arc-free-by-tag"

# 0) (opcional) New-AzResourceGroup -Name $ResourceGroup -Location $Location

# 1) Criar/atualizar policy set
$polSet = New-AzPolicySetDefinition `
  -Name $polSetName `
  -PolicyDefinition (Get-Content -Raw -Path "./policy/definition.json" | ConvertFrom-Json).properties.policyDefinitions `
  -Parameter (Get-Content -Raw -Path "./policy/parameters.example.json" | ConvertFrom-Json).parameters `
  -DisplayName "Arc em Free por TAG (Disable + Inherit)" `
  -Description "Mantém Azure VMs em P2 e Arc em Free via TAG herdada + disable resource-level" `
  -Metadata @{ category = "Security Center"; owner="SecOps/Cloud" } `
  -SubscriptionId $SubscriptionId

# 2) Assignment no RG
$assign = New-AzPolicyAssignment `
  -Name "rg-arc-free-by-tag" `
  -DisplayName "RG-ARC | Arc em Free por TAG (Disable + Inherit)" `
  -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" `
  -PolicySetDefinition $polSet `
  -Location $Location `
  -AssignIdentity `
  -PolicyParameterObject (Get-Content -Raw -Path "./policy/parameters.example.json" | ConvertFrom-Json)

# 3) Remediation tasks
Start-AzPolicyRemediation -Name "remediate-inherit-tag" -PolicyAssignmentId $assign.ResourceId -LocationFilter $Location -ResourceDiscoveryMode ReEvaluateCompliance
Start-AzPolicyRemediation -Name "remediate-disable-by-tag" -PolicyAssignmentId $assign.ResourceId -LocationFilter $Location -ResourceDiscoveryMode ReEvaluateCompliance


7) Passo a passo — Deploy, teste e validação

RG de controle

Crie/eleja o RG onde os Arc serão conectados (ex.: rg-azurearc-itsbx-us, eastus).

Aplique TAG no RG: DefenderForServers=Disabled.

Publicar a Initiative e assign no RG

Use os scripts acima ou o Portal (Policy → Definitions/Assignments).

A assignment cria System Assigned MI; conceda Contributor/Tag Contributor no RG.

Remediation

Crie tasks para: (1) herdar TAG e (2) desabilitar por TAG em recursos existentes.

Marque Re-evaluate compliance before remediating e defina Location correta.

Onboard Arc

azcmagent connect apontando para o RG e região; se quiser, inclua --tags DefenderForServers=Disabled.

Se já houve MDE, offboarding + remover extensão.

Validar compliance (pode levar alguns minutos).

Se a policy “ficar vermelha” por checar o pricingTier na assinatura, considere Manage/Customize coverage por TAG ou Exemption.

Validar por KQL (ARG)

TAGs nas máquinas Arc
Resources
| where resourceGroup == "<RG_ARC>"
| where type == "microsoft.hybridcompute/machines"
| project name, location, tags

Plano “Free” por máquina

SecurityResources
| where type == "microsoft.security/pricings"
| where name == "virtualMachines"
| extend Plan = tostring(properties.pricingTier),
         MachineName = extract(@"/machines/([^/]+)/providers", 1, id)
| where resourceGroup == "<RG_ARC>"
| project MachineName, Plan
| order by MachineName asc

Extensões MDE ainda presentes

Resources
| where resourceGroup == "<RG_ARC>"
| where type =~ "microsoft.hybridcompute/machines/extensions"
| where name endswith "/MDE.Windows" or name endswith "/MDE.Linux"
| project machine = split(name,"/")[0], extension = split(name,"/")[1], location


Validar custos

Cost Management → Cost analysis

Service: Microsoft Defender for Cloud

Meter: Defender for Servers

Resource Group: <RG_ARC>

Esperado: 0 (após ciclo de faturamento).


8) Boas práticas e observações

P2 ON para Azure VMs; Arc controlado via TAG/Policy (Free no resource-level).

Compliance ≠ Cobrança: se o check da policy é na assinatura, pode mostrar Non-compliant; use coverage por TAG ou Exemptions para “verde”.

Permissões: MI da assignment precisa de RBAC para remediation.

MDE: se não quiser EDR, remover extensão e offboard (só remover extensão não tira device do portal).

Auto-provisioning (Defender for Cloud) Off para não reinstalar MDE nos Arc.

Naming/Versioning: padronize nomes (RG-ARC-*), use metadata.version semântico, mantenha TAG estável.

9) Troubleshooting

Remediation “0 of 0”: habilite Re-evaluate compliance + confirme Location e recursos “non-compliant”.

Parâmetros não aparecem: desmarque “Only show parameters that need input or review”.

Erro de MI/role: garanta Owner/User Access Administrator no escopo.

MDE ainda no portal: faltou offboarding.

Policy “vermelha”: limitação do check; use coverage por TAG ou Exemption.

10) Melhorias futuras

Template Bicep/ARM para policy/assignment/remediations.

Pipeline (ADO/GitHub Actions) para promover entre ambientes.

Workbook com KQL (TAGs, MDE, custos).

Variação de TAG para P1/P2 por RG, se necessário.

11) Referências (adicione os links oficiais)

Azure Policy (definitions, assignments, remediation, managed identity)

Defender for Cloud (Defender for Servers P1/P2, Manage/Customize coverage por TAG, Auto-provisioning)

Azure Arc (Servers, Extensions, azcmagent connect)

Defender for Endpoint (offboarding Windows/Linux)

12) Changelog

2025-10-03 — v1.0.0

Initiative (policySet) com TAG inherit + disable por TAG.

Scripts de deploy (CLI/PowerShell).

Passo a passo de remediation, validação (KQL) e custo.

Notas de arquitetura e troubleshooting.

13) TODO (antes do publish)

 Substituir <ID_BUILTIN_INHERIT_TAG> e <ID_BUILTIN_DISABLE_DEFENDER_BY_TAG> pelos IDs reais (use az policy definition list).

 Incluir links oficiais (docs Microsoft) relevantes.

 Se a built-in de disable exigir pricingTier=Free na assinatura para “verde”, documentar coverage por TAG como alternativa de compliance.

::contentReference[oaicite:0]{index=0}







