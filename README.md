# Azure Virtual WAN / ISV NVA Demo

This repository deploys a disposable Azure demo that routes traffic between a customer workload VNet and an ISV workload VNet through a pair of ISV-managed Linux forwarding appliances. It implements the architecture and ownership boundaries in [design.md](design.md).

> **Cost warning:** Azure Bastion Standard and the Standard Virtual WAN hub are continuously billed while deployed. Destroy the roots in the documented order as soon as verification is complete.

## Architecture and ownership

The solution has four independent Terraform roots and four independent local state files:

| Root | Owner | Responsibility |
|---|---|---|
| `01-isv-core` | ISV | ISV VNet, Bastion, workload VM, NVA pair, and internal HA Ports load balancer |
| `02-customer-core` | Customer | Virtual WAN/hub, customer VNet, Bastion, workload VM, and customer workload connection |
| `03-isv-routing` | ISV | Customer-specific UDR and ISV workload-subnet association |
| `04-customer-connection` | Customer | ISV hub connection and connection-level static routing |

No Azure resource is managed by more than one root. Cross-root values are copied explicitly from structured Terraform outputs; the roots do not read each other's state.

See [architecture.svg](diagrams/architecture.svg) for the rendered topology and [architecture.drawio](diagrams/architecture.drawio) for the editable source. Implementation decisions and current status are recorded in [implementation-log.md](docs/implementation-log.md).

## Prerequisites

- Bash in WSL or Linux.
- Azure CLI authenticated to the target subscription.
- Terraform `1.16.3`.
- `jq` for loading verification variables from Terraform output JSON.
- An identity allowed to create resource groups, networking, compute, public IP, Bastion, and Virtual WAN resources.
- Registered `Microsoft.Network` and `Microsoft.Compute` resource providers.
- A conflict-free address plan, including comparison with every VNet and branch connected to the target Virtual WAN.
- A local Ed25519 SSH key. The demo configuration expects:

  ```bash
  ~/.ssh/ecs-vwan-fwaas-demo
  ~/.ssh/ecs-vwan-fwaas-demo.pub
  ```

  Generate it if needed:

  ```bash
  install -d -m 700 ~/.ssh
  ssh-keygen -t ed25519 -f ~/.ssh/ecs-vwan-fwaas-demo -C ecs-vwan-fwaas-demo
  chmod 600 ~/.ssh/ecs-vwan-fwaas-demo
  chmod 644 ~/.ssh/ecs-vwan-fwaas-demo.pub
  ```

The checked-in demo values target Sweden Central and use:

| Network | Prefix |
|---|---|
| Virtual hub | `10.0.0.0/23` |
| Customer VNet / workload / Bastion | `10.10.0.0/16`, `10.10.1.0/24`, `10.10.255.0/26` |
| ISV VNet / NVA / workload / Bastion | `10.100.0.0/16`, `10.100.0.0/24`, `10.100.1.0/24`, `10.100.255.0/26` |
| NVA load-balancer frontend | `10.100.0.10` |

## Preflight

Set the target subscription and confirm the active identity before changing any infrastructure:

```bash
az account set --subscription "<subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' -o table
az provider show --namespace Microsoft.Network --query registrationState -o tsv
az provider show --namespace Microsoft.Compute --query registrationState -o tsv
az vm list-skus \
  --location swedencentral \
  --size Standard_B2s \
  --resource-type virtualMachines \
  --all \
  --query "[?name=='Standard_B2s'].{zones:locationInfo[0].zones,restrictions:restrictions}" \
  -o json
```

Before applying, compare the demo prefixes with existing VNet and Virtual WAN route prefixes:

```bash
az network vnet list \
  --query "[].{name:name,resourceGroup:resourceGroup,prefixes:addressSpace.addressPrefixes}" \
  -o table
```

Also inspect branch prefixes and effective hub routes in the target Virtual WAN. Terraform validates containment and overlap within each root, but it cannot prove that the proposed ranges do not conflict with external networks.

## Configure inputs

Each root contains a `demo.tfvars` with non-secret demo values. Set the same subscription ID in every file and review all names, prefixes, VM sizes, zones, usernames, and the SSH public-key path.

Local state is intentional. Keep each root's `.terraform` directory and state files until its resources are destroyed. Never commit state or plan files.

## Initialize and validate

Run these commands from the repository root:

```bash
for root in 01-isv-core 02-customer-core 03-isv-routing 04-customer-connection; do
  terraform -chdir="$root" init -input=false
  terraform -chdir="$root" fmt -check
  terraform -chdir="$root" validate
done
```

## Deploy

### 1. ISV core

```bash
terraform -chdir=01-isv-core plan \
  -input=false \
  -var-file=demo.tfvars \
  -out=isv-core.tfplan
terraform -chdir=01-isv-core apply -input=false isv-core.tfplan
terraform -chdir=01-isv-core output
```

Wait for cloud-init to finish on both NVAs and confirm both load-balancer backends are healthy before proceeding. The commands are in [verification.md](docs/verification.md).

### 2. Customer core

```bash
terraform -chdir=02-customer-core plan \
  -input=false \
  -var-file=demo.tfvars \
  -out=customer-core.tfplan
terraform -chdir=02-customer-core apply -input=false customer-core.tfplan
terraform -chdir=02-customer-core output
```

Virtual hub provisioning can take a long time. Do not continue until the hub and customer workload connection report success.

### 3. ISV return routing

Copy the ISV workload subnet ID, customer VNet CIDR, and NVA frontend IP into `03-isv-routing/demo.tfvars`.

```bash
terraform -chdir=03-isv-routing plan \
  -input=false \
  -var-file=demo.tfvars \
  -out=isv-routing.tfplan
terraform -chdir=03-isv-routing apply -input=false isv-routing.tfplan
```

### 4. Customer-managed ISV connection

Copy the virtual hub ID and default route-table ID from `02-customer-core`, and the ISV VNet ID, ISV workload CIDR, and NVA frontend IP from `01-isv-core`, into `04-customer-connection/demo.tfvars`.

```bash
terraform -chdir=04-customer-connection plan \
  -input=false \
  -var-file=demo.tfvars \
  -out=customer-connection.tfplan
terraform -chdir=04-customer-connection apply -input=false customer-connection.tfplan
```

The ISV connection is created with `static_vnet_local_route_override_criteria = "Contains"`. Azure only supports this setting at connection creation; changing it replaces the connection.

## Verify

Follow [verification.md](docs/verification.md). Verification must establish all of the following:

- Both directions work independently.
- NVA counters increase for each test.
- The destination observes the original workload VM address, proving no SNAT.
- Traffic continues after either NVA is stopped and the load-balancer probe converges.
- Removing the ISV UDR or customer-side connection produces the documented negative result.

Route output alone does not prove NVA traversal.

## Troubleshooting

- **Hub or connection still provisioning:** wait and recheck. Virtual WAN operations routinely take longer than VNet operations.
- **NVA backend unhealthy:** connect through ISV Bastion, inspect `cloud-init status --long`, `systemctl status forwarding-health.socket`, and the probe listener.
- **One-way traffic:** verify the ISV workload-subnet UDR exists and that the NVA subnet has no route-table association.
- **Traffic bypasses the NVA:** check the propagated hub route, connection static route, and local-route override criterion.
- **The NVA frontend does not answer ping:** Floating IP is enabled for the HA Ports rule and the frontend address is not configured on an NVA loopback. Test end-to-end workload traffic and inspect NVA counters instead.
- **SSH fails:** confirm Bastion native-client tunneling is enabled, the correct private key is used, and the NSG permits SSH only from the local `AzureBastionSubnet`.
- **Plan wants to recreate the ISV connection:** inspect changes to the virtual hub, remote VNet, connection name, or local-route override criterion before applying.

## Destroy

Destroy in the reverse dependency order:

```bash
terraform -chdir=04-customer-connection destroy -input=false -var-file=demo.tfvars
terraform -chdir=03-isv-routing destroy -input=false -var-file=demo.tfvars
terraform -chdir=02-customer-core destroy -input=false -var-file=demo.tfvars
terraform -chdir=01-isv-core destroy -input=false -var-file=demo.tfvars
```

Then verify that no billable resources remain:

```bash
az group list \
  --query "[?contains(name, 'vwan') || contains(name, 'nva')].{name:name,state:properties.provisioningState}" \
  -o table
```

Do not delete local state until Azure confirms that all four roots have been destroyed.
