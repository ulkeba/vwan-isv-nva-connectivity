# Azure Virtual WAN / ISV NVA Demo

Deploy a disposable customer/ISV topology and verify whether traffic crosses ISV-managed Linux forwarding appliances without source NAT (SNAT). The example uses one NVA; the configuration supports one to three.

- [Design](design.md): ownership, address plan, and routing constraints.
- [Verification](docs/verification.md): interactive traffic inspection and live Firewall logs.
- [Diagram](diagrams/architecture.svg): reference topology.
- [Implementation log](docs/implementation-log.md): historical development record.

> **Cost warning:** Bastion Standard, the Virtual WAN hub, optional Firewall, VMs, and logging incur charges. [Destroy](#destroy) the demo when finished.

## Deployment order

| Root | Owner | Responsibility |
|---|---|---|
| `01-isv-core` | ISV | ISV network, NVA cluster, workload, Bastion |
| `02-customer-core` | Customer | Customer network, Virtual WAN/hub, workload, Bastion, optional Firewall |
| `03-isv-routing` | ISV | Return-path UDR on the ISV workload subnet |
| `04-customer-connection` | Customer | VNet Connection and static route from customer VWAN hub to ISV network|

Each root has independent local state. Cross-root values are copied explicitly from outputs. Deploy in table order and destroy in reverse order.

## Prerequisites

- Zsh on macOS, Linux, or WSL, Azure CLI, Terraform **1.16.3**, `jq`, and OpenSSH.
- An Azure identity permitted to create the demo resources in the target subscription. This walkthrough uses the same subscription for all roots.
- Available regional VM SKUs, sufficient quotas, and non-overlapping VNet/hub ranges; see the [reference address plan](design.md#address-and-naming-contracts).
- An SSH key matching both core roots' public-key inputs.

Run local commands from the repository root in one Zsh session. Run the command blocks in order, inspect their output, and **stop and fix every reported error before continuing**. These are interactive instructions, not an automatically aborting script. Enable pipeline error reporting:

```zsh
set -o pipefail
for tool in az terraform jq ssh; do
  if ! command -v "$tool" >/dev/null; then
    printf 'ERROR: %s is missing. Install it and ensure it is on PATH before continuing.\n' "$tool" >&2
    false
  fi
done
if [[ ! -f README.md || ! -d 01-isv-core ]]; then
  printf 'ERROR: Wrong working directory: %s. Change to the repository root before running these commands.\n' "$PWD" >&2
  false
fi
```

Generate the example key only if it does not already exist:

```zsh
install -d -m 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/fd-fwaas-demo -C fd-fwaas-demo
chmod 600 ~/.ssh/fd-fwaas-demo
chmod 644 ~/.ssh/fd-fwaas-demo.pub
```

## Configure a local deployment

Keep the sanitized `demo.tfvars` files unchanged. Copy them to ignored local configuration files under a deployment name of your choice:

```zsh
export DEPLOYMENT_NAME=local-demo
export TF_WORKSPACE="$DEPLOYMENT_NAME"
export EVIDENCE_DIR="evidence_$DEPLOYMENT_NAME"

if [[ ! "$DEPLOYMENT_NAME" =~ ^[[:alnum:]][[:alnum:]_-]*$ ]]; then
  printf 'ERROR: Invalid deployment name "%s". Use a letter or digit first, then letters, digits, underscores, or hyphens.\n' "$DEPLOYMENT_NAME" >&2
  false
fi
```

Once the deployment name is valid, create the local copies:

```zsh
for root in 01-isv-core 02-customer-core 03-isv-routing 04-customer-connection; do
  if test -e "$root/$DEPLOYMENT_NAME.tfvars"; then
    printf 'Keeping existing configuration: %s\n' "$root/$DEPLOYMENT_NAME.tfvars"
  elif ! cp "$root/demo.tfvars" "$root/$DEPLOYMENT_NAME.tfvars"; then
    printf 'ERROR: Could not copy %s/demo.tfvars. Check the repository location and write permissions before retrying.\n' "$root" >&2
    break
  fi
done
mkdir -p "$EVIDENCE_DIR"
```

Names must begin with a letter or digit and contain only letters, digits, underscores, or hyphens. Every root must have a non-empty matching tfvars file. `TF_WORKSPACE` selects the same shell-local workspace for all Terraform commands; do not switch to the default workspace partway through. `env_demo.sh` is an optional example of these three exports, not an Azure authentication or account-selection script.

Edit only the local copies, using these requirements:

**Required before planning the core deployments (01/02):**

- Replace `subscription_id = "00000000-0000-0000-0000-000000000000"` with your target subscription ID in all four files.
- Ensure root 01's `ssh_public_key_path` and root 02's `customer_workload_ssh_public_key_path` point to an existing SSH public key. Keep the example paths if you generated the key above.

**Change only if needed for your environment:**

- Change `location`, VM sizes, or zones if the example choices are unavailable or exceed your quotas. Keep `location` consistent in roots 01/02/03.
- Change address ranges/IPs if they overlap existing connected networks.
- Change resource prefixes if `demo-isv` or `demo-customer` are already in use by another deployment in the target subscription.

**Required after core deployment, before planning roots 03/04:**

Use the stage 3/4 tables below to copy resource IDs and next-hop IPs from actual core outputs. Root 03 needs the customer VNet prefix; root 04 needs the chosen ISV traffic range, matching the core forwarding and Firewall inputs, not necessarily the workload subnet. Replace the example IDs, including their embedded subscription/name segments, with actual output values rather than guessing resource names.

**Optional customization:** otherwise, the demo settings can stay unchanged. You may customize the region, VM count/size/zones, usernames, naming prefixes, the address plan, ISV forwarding scope, and Firewall/routing mode to suit your demo. Match `isv_prefix` in roots 01/03 and `customer_prefix` in roots 02/04. Keep forwarding, allowed, and routed ISV ranges consistent across roots; the example uses the full ISV VNet, not just its physical workload subnet.

**Example versus defaults:** the example sets one non-zonal NVA and enables Firewall plus Internet/Private Traffic Routing Intent. Terraform defaults are two NVAs with zones `["1", "2"]` and no Firewall. For instance redundancy, configure at least two NVAs; use `nva_zones = null` for regional VMs or exactly one distinct zone per NVA. Workload zone inputs also accept `null`.

Review [Routing Intent constraints](design.md#optional-firewall-and-routing-intent) before choosing a mode. A successful apply or connection does not establish NVA traversal.

## Authenticate and preflight

Replace these placeholders with values matching the local tfvars:

```zsh
export SUBSCRIPTION_ID="<subscription-id>"
export AZURE_REGION="<azure-region>"
export VM_SIZE="<vm-size>"

if [[ "$SUBSCRIPTION_ID" == "<subscription-id>" || "$AZURE_REGION" == "<azure-region>" || "$VM_SIZE" == "<vm-size>" ]]; then
  printf 'ERROR: Preflight placeholders are unchanged. Set SUBSCRIPTION_ID, AZURE_REGION, and VM_SIZE to match your local tfvars.\n' >&2
  false
fi
```

After replacing the placeholders, sign in and confirm the active subscription:

```zsh
az login &&
  az account set --subscription "$SUBSCRIPTION_ID" &&
  az account show --query '{name:name,id:id,tenantId:tenantId}' -o table
```

Then inspect providers, VM availability, quotas, and existing networks:

```zsh
for provider in Microsoft.Network Microsoft.Compute Microsoft.Insights Microsoft.OperationalInsights; do
  if ! az provider show --namespace "$provider" --query '{provider:namespace,state:registrationState}' -o table; then
    printf 'ERROR: Cannot inspect provider %s. Check subscription access and the Azure error above.\n' "$provider" >&2
    break
  fi
done
az vm list-skus \
  --location "$AZURE_REGION" --size "$VM_SIZE" \
  --resource-type virtualMachines --all \
  --query "[?name=='$VM_SIZE'].{zones:locationInfo[0].zones,restrictions:restrictions}" -o json
az vm list-usage --location "$AZURE_REGION" -o table
az network vnet list \
  --query "[].{name:name,resourceGroup:resourceGroup,prefixes:addressSpace.addressPrefixes}" -o table
```

Require registered Network/Compute providers, plus Insights/OperationalInsights when Firewall logging is enabled. Check each selected VM size, quotas, and connected branch/hub routes. Local Terraform validation cannot detect every external address conflict.

## Initialize and validate

```zsh
if [[ -z "${DEPLOYMENT_NAME:-}" || ! "$DEPLOYMENT_NAME" =~ ^[[:alnum:]][[:alnum:]_-]*$ ]]; then
  printf 'ERROR: Missing or invalid DEPLOYMENT_NAME. Set the local deployment name from Configure a local deployment.\n' >&2
  false
fi
if [[ -z "${TF_WORKSPACE:-}" || "$TF_WORKSPACE" != "${DEPLOYMENT_NAME:-}" ]]; then
  printf 'ERROR: TF_WORKSPACE="%s" must match DEPLOYMENT_NAME="%s". Run: export TF_WORKSPACE="$DEPLOYMENT_NAME"\n' "${TF_WORKSPACE:-<unset>}" "${DEPLOYMENT_NAME:-<unset>}" >&2
  false
fi
for root in 01-isv-core 02-customer-core 03-isv-routing 04-customer-connection; do
  if [[ ! -s "$root/$DEPLOYMENT_NAME.tfvars" ]]; then
    printf 'ERROR: Missing or empty %s/%s.tfvars. Copy the demo template and configure the inputs before initializing.\n' "$root" "$DEPLOYMENT_NAME" >&2
    false
  fi
done
```

Resolve all precheck errors, then initialize each root against `default`. The command-local override leaves your exported deployment `TF_WORKSPACE` unchanged. With this repository's local backend and Terraform 1.16.3, the first plan creates the named workspace directory if it does not exist; no explicit workspace-creation command is needed.

```zsh
for root in 01-isv-core 02-customer-core 03-isv-routing 04-customer-connection; do
  if TF_WORKSPACE=default terraform -chdir="$root" init -input=false &&
    terraform -chdir="$root" fmt -check &&
    terraform -chdir="$root" validate; then
    printf 'Initialized and validated %s\n' "$root"
  else
    printf 'ERROR: Initialization, formatting, or validation failed in %s. Correct the reported error before planning.\n' "$root" >&2
    break
  fi
done
```

The loop stops on the first failure. A newly created workspace has empty state: for an existing deployment, use its original deployment name and retain its state rather than creating a differently named workspace. Recheck workspace setup if you change backend type; other backends may require explicit workspace creation.

Use the same environment for plan, apply, output, and destroy. Never commit state, plans, evidence, keys, or real environment configuration.

## Deploy

Run each plan first and review its output before running the separate apply/output block. Saved plans apply without another confirmation. Terraform VM extensions wait for cloud-init and validate testing tools; the NVA extension also checks forwarding and its probe responder. Any extension failure is a deployment failure.

Each root uses `$DEPLOYMENT_NAME.tfplan`: `-chdir` saves and reads the relative plan path inside that root, so a stage suffix is redundant. The deployment name distinguishes plans for different deployments within the same root.

### 1. ISV core

```zsh
terraform -chdir=01-isv-core plan -input=false \
  -var-file="$DEPLOYMENT_NAME.tfvars" -out="$DEPLOYMENT_NAME.tfplan"
```

```zsh
terraform -chdir=01-isv-core apply -input=false "$DEPLOYMENT_NAME.tfplan" &&
  terraform -chdir=01-isv-core output -json > "$EVIDENCE_DIR/01-isv-core.json"
```

Before continuing, confirm each NVA's health-check extension reports `Succeeded`, then check the load balancer's **Health Probe Status** metric in Azure Monitor for every backend:

```zsh
if nva_ids=$(jq -er '.nva_virtual_machines.value[].id' "$EVIDENCE_DIR/01-isv-core.json"); then
  while IFS= read -r nva_id; do
    if ! az vm extension list --ids "$nva_id" \
      --query "[].{name:name,state:provisioningState}" -o table; then
      printf 'ERROR: Cannot inspect VM extensions for %s. Check subscription access and provisioning before continuing.\n' "$nva_id" >&2
      break
    fi
  done <<< "$nva_ids"
else
  printf 'ERROR: Cannot read NVA IDs from %s/01-isv-core.json. Capture successful root 01 outputs before checking extensions.\n' "$EVIDENCE_DIR" >&2
  false
fi
```

### 2. Customer core

```zsh
terraform -chdir=02-customer-core plan -input=false \
  -var-file="$DEPLOYMENT_NAME.tfvars" -out="$DEPLOYMENT_NAME.tfplan"
```

```zsh
terraform -chdir=02-customer-core apply -input=false "$DEPLOYMENT_NAME.tfplan" &&
  terraform -chdir=02-customer-core output -json > "$EVIDENCE_DIR/02-customer-core.json" &&
  source ./environment.sh
```

After apply, output capture, and environment loading succeed, check readiness:

```zsh
az network vhub show --ids "$VIRTUAL_HUB_ID" \
  --query '{provisioning:provisioningState,routing:routingState}' -o table
az network vhub connection show --ids "$CUSTOMER_WORKLOAD_CONNECTION_ID" \
  --query '{name:name,state:provisioningState}' -o table
```

Wait for hub provisioning `Succeeded`, routing `Provisioned`, and connection `Succeeded`. `environment.sh` can load core outputs before stages 03/04 exist.

### 3. ISV return routing

Update `03-isv-routing/$DEPLOYMENT_NAME.tfvars` from these sources:

| Input | Source |
|---|---|
| `isv_workload_subnet_id` | Root 01: `isv_workload_subnet.id` |
| `nva_frontend_private_ip_address` | Root 01: `nva_load_balancer.frontend_ip` |
| `customer_address_prefix` | Root 02: `customer_virtual_network.address_spaces[0]` |

Inspect fields with `terraform -chdir=<root> output -json` or the captured JSON (`.OUTPUT_NAME.value.FIELD`).

```zsh
terraform -chdir=03-isv-routing plan -input=false \
  -var-file="$DEPLOYMENT_NAME.tfvars" -out="$DEPLOYMENT_NAME.tfplan"
```

```zsh
terraform -chdir=03-isv-routing apply -input=false "$DEPLOYMENT_NAME.tfplan" &&
  terraform -chdir=03-isv-routing output -json > "$EVIDENCE_DIR/03-isv-routing.json"
```

### 4. Customer-managed ISV connection

Update `04-customer-connection/$DEPLOYMENT_NAME.tfvars`:

| Input | Source |
|---|---|
| `virtual_hub_id` | Root 02: `customer_virtual_hub.id` |
| `associated_route_table_id` | Root 02: `customer_virtual_hub.default_route_table_id` |
| `isv_virtual_network_id` | Root 01: `isv_virtual_network.id` |
| `nva_load_balancer_frontend_ip_address` | Root 01: `nva_load_balancer.frontend_ip` |
| `isv_workload_address_prefix` | Chosen traffic range, matching root 01 forwarding and root 02 rules |

```zsh
terraform -chdir=04-customer-connection plan -input=false \
  -var-file="$DEPLOYMENT_NAME.tfvars" -out="$DEPLOYMENT_NAME.tfplan"
```

```zsh
terraform -chdir=04-customer-connection apply -input=false "$DEPLOYMENT_NAME.tfplan" &&
  terraform -chdir=04-customer-connection output -json > "$EVIDENCE_DIR/04-customer-connection.json"
```

Changing the connection's bypass setting can require replacement; inspect replacement plans before applying.

## Verify and troubleshoot

Follow [verification.md](docs/verification.md) to inspect a customer-initiated TCP flow interactively with Bastion SSH, tcpdump, and netcat. Verify NVA ingress/egress for both requests and replies and the receiver-observed source IP, then follow Firewall logs in a separate terminal when enabled. Deployment-state and route checks are in the guide's Troubleshooting section. Routes alone do not prove traversal.

| Symptom | Check |
|---|---|
| Hub/connection still provisioning | Wait for successful provisioning and `Provisioned` routing |
| NVA probe unhealthy | Bastion SSH: `cloud-init status --long`, `systemctl status forwarding-health.socket`, probe listener |
| One-way traffic | Workload-subnet UDR, NVA hub route, allowed/forwarded ranges |
| NVA bypass | Connection static route, bypass setting, Routing Intent, packet captures |
| Frontend does not answer ping | Test workloads instead; the frontend is a next hop, not an NVA loopback |
| SSH/tunnel failure | Bastion tunneling, correct key/user, subscription, NSGs |

## Destroy

**Before destroying either core**, capture the six actual resource-group IDs. This avoids relying on hard-coded prefixes or outputs that disappear:

```zsh
terraform -chdir=01-isv-core output -json > "$EVIDENCE_DIR/01-isv-core.json" &&
  terraform -chdir=02-customer-core output -json > "$EVIDENCE_DIR/02-customer-core.json" &&
  jq -er '.isv_resource_groups.value[].id' "$EVIDENCE_DIR/01-isv-core.json" \
    > "$EVIDENCE_DIR/resource-group-ids.txt" &&
  jq -er '.customer_resource_groups.value[].id' "$EVIDENCE_DIR/02-customer-core.json" \
    >> "$EVIDENCE_DIR/resource-group-ids.txt"
```

Only continue after the capture succeeds and the inventory contains six IDs:

```zsh
if [[ ! -s "$EVIDENCE_DIR/resource-group-ids.txt" ]]; then
  printf 'ERROR: Resource-group inventory is missing. Capture successful core outputs before destroying resources.\n' >&2
  false
elif [[ "$(wc -l < "$EVIDENCE_DIR/resource-group-ids.txt")" -ne 6 ]]; then
  printf 'ERROR: Expected six resource-group IDs in %s/resource-group-ids.txt. Verify both core outputs before destroying resources.\n' "$EVIDENCE_DIR" >&2
  false
fi
```

```zsh
terraform -chdir=04-customer-connection destroy -var-file="$DEPLOYMENT_NAME.tfvars" &&
  terraform -chdir=03-isv-routing destroy -var-file="$DEPLOYMENT_NAME.tfvars" &&
  terraform -chdir=02-customer-core destroy -var-file="$DEPLOYMENT_NAME.tfvars" &&
  terraform -chdir=01-isv-core destroy -var-file="$DEPLOYMENT_NAME.tfvars"
```

Review each interactive confirmation. The chain stops if a destroy fails or is cancelled. Then check every captured group; any API error or remaining group requires investigation, regardless of the last command's exit status:

```zsh
while IFS= read -r group_id; do
  if exists=$(az group exists --subscription "$(cut -d/ -f3 <<< "$group_id")" \
    --name "${group_id##*/}" -o tsv); then
    printf '%s exists: %s\n' "$group_id" "$exists"
    if [[ "$exists" != false ]]; then
      printf 'ERROR: Resource group %s is still present or returned an unexpected status. Inspect its resources and finish teardown before deleting state.\n' "$group_id" >&2
      false
    fi
  else
    printf 'ERROR: Cannot check deletion of %s. Resolve the Azure authentication/API error; retain state until deletion is confirmed.\n' "$group_id" >&2
    false
  fi
done < "$EVIDENCE_DIR/resource-group-ids.txt"
```

An API/authentication error is not proof of deletion. Confirm all six groups and their billable resources are gone before removing state. Retain evidence until results and cleanup have been reviewed.
