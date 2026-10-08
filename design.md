# Azure Virtual WAN / ISV NVA Demo

## 1. Purpose

Build a disposable Azure demo that proves traffic between a customer workload VNet and an ISV workload VNet can be routed transparently through an ISV-managed NVA cluster.

The demo has three business lifecycles implemented by four independently owned Terraform deployments:

1. ISV core: ISV VNet, workload, NVA instances, load balancer, and management access.
2. Customer core: Virtual WAN, customer workload VNet, and management access.
3. Onboarding:
   - ISV routing: customer-specific UDR on the ISV workload subnet.
   - Customer connection: Virtual WAN connection to the ISV VNet and its static route.

Terraform deploys the infrastructure. Cloud-init and systemd configure the Linux forwarding VMs.

## 2. Scope

### In scope

- One Azure region and one Virtual WAN virtual hub.
- One customer workload VNet connected to the virtual hub.
- Optional Azure Firewall with Internet and optional Private Traffic Routing Intent.
- One ISV VNet with a workload subnet, an NVA subnet, and one to three optionally zonal Linux forwarding VMs.
- A Standard internal load balancer with an HA Ports rule as the stable NVA next hop.
- One public IP per NVA for NVA-originated outbound connectivity.
- Transparent routing without SNAT for traffic initiated in either direction.
- Azure Bastion Standard with native SSH connectivity for each core VNet.
- Four Terraform roots with separate state and ownership.
- WSL-compatible Bash scripts, an interactive verification guide, and a draw.io diagram.

### Out of scope

- Hub-integrated NVAs, ExpressRoute, VPN, ISV workload internet inspection, multi-hub routing, IPv6, DNS integration, and production firewall policy.
- VM scale sets, autoscaling, production hardening, patch management, and stateful firewall failover.
- Cross-tenant authorization automation. The deployment identity must already have access to the required subscriptions.

## 3. Architecture decisions

### AD-01: Use a spoke NVA

The NVA cluster runs in the ISV VNet. Virtual WAN connection-level static
routes direct private traffic to the internal load-balancer frontend. Internet
Traffic Routing Intent applies to customer workload internet traffic; optional
Private Traffic Routing Intent also attracts private traffic and requires live
path verification.

Reference: [Static routes in Virtual WAN](https://learn.microsoft.com/azure/virtual-wan/static-routes)

### AD-02: Propagate the connection static route

The customer-side connection deployment creates the ISV virtual hub connection with:

- a static route for the configured ISV destination prefix;
- the NVA load-balancer frontend as next-hop IP;
- static-route propagation enabled;
- caller-supplied associated and propagated hub route-table IDs or labels.

The demo values use `defaultRouteTable`, but this is not required. A customer-defined route table works when the customer workload connection is associated with a table receiving the propagated ISV route and the ISV connection can learn the customer route.

References:

- [Virtual hub route association and propagation](https://learn.microsoft.com/azure/virtual-wan/about-virtual-hub-routing)
- [Static routes in Virtual WAN](https://learn.microsoft.com/azure/virtual-wan/static-routes)

### AD-03: Do not bypass the NVA for the ISV workload

Set `static_vnet_local_route_override_criteria = "Contains"` on the ISV virtual hub connection. This corresponds to **Bypass Next Hop IP for workloads within this VNet = No** and keeps the ISV workload behind the NVA route.

Azure only allows this property to be set when the connection is created. Changing it requires replacement of the connection.

Reference: [Bypass Next Hop IP for workloads within this VNet](https://learn.microsoft.com/azure/virtual-wan/howto-connect-vnet-hub#understanding-bypass-next-hop-ip-for-workloads-within-this-vnet)

### AD-04: Use one to three individual NVA VMs

Deploy one to three `azurerm_linux_virtual_machine` resources, with two
instances by default. When `nva_zones` is non-null, each VM uses the
corresponding distinct availability zone. When `nva_zones = null`, the VMs and
their Standard public IPs are regional/non-zonal so the design can deploy in a
region without Availability Zones. A VM scale set adds orchestration unrelated
to this routing demo and makes instance-level failover testing less explicit.

Each NVA has one NIC and one IP configuration. Every NIC joins one Standard internal load-balancer backend pool with:

- one private frontend IP in the NVA subnet;
- one HA Ports rule with protocol `All` and ports `0`;
- Floating IP enabled;
- one TCP health probe.

Reference: [Azure Load Balancer HA Ports](https://learn.microsoft.com/azure/load-balancer/load-balancer-ha-ports-overview)

Non-zonal instances retain load-balancer/instance redundancy when more than one
NVA is deployed, but they do not provide explicit zone-failure isolation.

### AD-05: Enforce the ISV return path with a UDR

The ISV-routing deployment associates a route table with the ISV workload subnet:

| Destination | Next hop type | Next hop |
|---|---|---|
| Customer VNet CIDR | Virtual appliance | NVA load-balancer frontend IP |

Do not associate this route table with the NVA subnet. After forwarding, the NVA uses the route learned from the virtual hub to reach the customer workload.

### AD-06: Use Bastion Standard for management

Each core deployment creates one Azure Bastion Standard host with native-client tunneling enabled. Each VNet contains an `AzureBastionSubnet` of at least `/26` and a Standard public IP for Bastion. VMs have no public IPs, and SSH is allowed only from the Bastion subnet.

Developers connect from WSL with the Azure CLI and native SSH client.

References:

- [Azure Bastion overview](https://learn.microsoft.com/azure/bastion/bastion-overview)
- [Connect with the Linux native client](https://learn.microsoft.com/azure/bastion/connect-vm-native-client-linux)

### AD-07: Make customer firewall routing optional

`virtual_hub_deploy_firewall` conditionally deploys a Standard `AZFW_Hub`
firewall, Firewall Policy, rules, and Internet Traffic routing intent. Only the
customer workload connection enables Internet Security and learns
`0.0.0.0/0` through Azure Firewall.

By default, Private Traffic routing intent is omitted. Private routes then
use the connection static route for the configured ISV destination prefix.
Return traffic uses the ISV workload UDR for the configured customer address
prefix. `virtual_hub_route_private_traffic` optionally adds the Private Traffic
policy. Root 04 does not supply an explicit propagated-route-table block;
Azure control-plane acceptance and the resulting Firewall/NVA path require
live verification.

The demo policy allows traffic between the configured customer and ISV
traffic prefixes, allows HTTP/HTTPS from either prefix to all FQDNs except
`www.facebook.com`, and otherwise uses Azure Firewall's default deny. It does
not add separate infrastructure exclusions or deny collections.

References:

- [Securing internet access with routing intent](https://learn.microsoft.com/azure/virtual-wan/about-internet-routing)
- [Azure Firewall rule processing](https://learn.microsoft.com/azure/firewall/rule-processing)

## 4. Demo address plan

These values are supplied explicitly through each root's
`${DEPLOYMENT_NAME}.tfvars`; CIDR and IP variables have no Terraform defaults.

| Network | Demo value |
|---|---|
| Virtual hub | `10.0.0.0/23` |
| Customer VNet | `10.10.0.0/16` |
| Customer workload subnet | `10.10.1.0/24` |
| Customer Bastion subnet | `10.10.255.0/26` |
| ISV VNet | `192.168.0.0/16` |
| ISV NVA subnet | `192.168.0.0/24` |
| NVA load-balancer frontend | `192.168.0.10` |
| ISV workload subnet | `192.168.1.0/24` |
| ISV Bastion subnet | `192.168.255.0/26` |

The forwarding and routing inputs may cover the full ISV VNet while the
physical workload subnet remains unchanged. Additional workload subnets
require their own appropriate NSGs and customer return-path UDR association;
infrastructure subnets must not receive that UDR.
Absence of a subnet UDR does not prevent private traffic arriving from the hub:
the aggregate route and local-route override still affect those destinations.

Cross-input consistency checks belong in `validations.tf`, separate from the effective network configuration. They must reject overlaps, invalid containment, an NVA frontend outside the NVA subnet, and an invalid Bastion subnet prefix.

The runbook must also check the proposed ranges against existing connected VNet and branch prefixes.

## 5. Expected packet paths

### Customer to ISV

1. The customer VM sends traffic to the ISV workload IP.
2. Its hub route table selects the propagated ISV static route.
3. The ISV connection redirects the packet to the NVA load-balancer frontend.
4. The load balancer selects a healthy NVA.
5. The NVA forwards the packet to the ISV workload without SNAT.

### ISV to customer

1. The ISV workload-subnet UDR sends traffic for the customer prefix to the NVA load-balancer frontend.
2. The load balancer selects a healthy NVA.
3. The NVA forwards the packet to the virtual hub without SNAT.
4. The hub sends the packet to the customer workload connection.

Tests must prove both directions independently. Connectivity alone does not prove NVA traversal.

## 6. Repository layout

```text
.
|-- design.md
|-- README.md
|-- docs/
|   `-- verification.md
|-- diagrams/
|   |-- architecture.drawio
|   `-- architecture.svg
|-- modules/
|   |-- linux-test-vm/
|   `-- linux-nva-cluster/
|-- 01-isv-core/
|   |-- backend.tf
|   |-- <deployment>.tfvars
|   |-- main.tf
|   |-- outputs.tf
|   |-- providers.tf
|   |-- validations.tf
|   `-- variables.tf
|-- 02-customer-core/
|   |-- backend.tf
|   |-- <deployment>.tfvars
|   |-- main.tf
|   |-- outputs.tf
|   |-- providers.tf
|   |-- validations.tf
|   `-- variables.tf
|-- 03-isv-routing/
|   |-- backend.tf
|   |-- <deployment>.tfvars
|   |-- main.tf
|   |-- outputs.tf
|   |-- providers.tf
|   |-- validations.tf
|   `-- variables.tf
|-- 04-customer-connection/
|   |-- backend.tf
|   |-- <deployment>.tfvars
|   |-- main.tf
|   |-- outputs.tf
|   |-- providers.tf
|   |-- validations.tf
|   `-- variables.tf
|-- cloud-init/
|   `-- testing-tools.yaml
|-- scripts/
|   |-- show-effective-routes.sh
|   |-- show-nva-counters.sh
|   `-- test-connectivity.sh
`-- nva/
    |-- cloud-init.yaml.tftpl
    |-- forwarding-health.service
    `-- forwarding-health.socket
```

Each numbered directory is a Terraform root with a separate backend key and lock. Reusable modules contain no provider or backend configuration.

## 7. State ownership and deployment contracts

| Root | Owner | Resources |
|---|---|---|
| `01-isv-core` | ISV | Network, workload, and Bastion resource groups; VNet/subnets/NSGs; NVA cluster; test workload; Bastion |
| `02-customer-core` | Customer | Network, workload, and Bastion resource groups; Virtual WAN/hub; VNet/subnets/NSGs; test workload; Bastion; workload connection |
| `03-isv-routing` | ISV | Customer-specific route table, route, and ISV workload-subnet association |
| `04-customer-connection` | Customer | ISV virtual hub connection and connection-level routing |

No Azure resource may be managed by more than one state file.

### Inputs

`03-isv-routing` requires:

- ISV workload subnet ID;
- customer VNet CIDR;
- NVA load-balancer frontend IP.

`04-customer-connection` requires:

- virtual hub ID;
- ISV VNet ID;
- ISV workload CIDR;
- NVA load-balancer frontend IP;
- associated hub route-table ID.

CIDR and IP variables are required and have no default values. Commands use
`-input=false -var-file="$DEPLOYMENT_NAME.tfvars"` so missing values fail
visibly.

Resource names derive from two optional variables with defaults: `isv_prefix = "fd-isv"` and `customer_prefix = "fd-customer"`. Role components (`network`, `workload`, and `bastion`) and resource-type suffixes are fixed in the configuration. Individual resource names are not inputs.

An override is a cross-root contract: roots 01 and 03 must receive the same `isv_prefix`, and roots 02 and 04 must receive the same `customer_prefix`.

NSG and route-table ownership is:

- `fd-isv-network-rg`: NVA, workload-subnet, and Bastion-subnet NSGs; customer route table and route.
- `fd-customer-network-rg`: workload-subnet and Bastion-subnet NSGs.
- Workload and Bastion resource groups contain no NSGs or route tables.
- Customer-side routing remains on Virtual Hub connections and Virtual Hub-managed route tables rather than a standalone route table.

### Outputs

Use one structured output per resource or repeated resource collection that consumers need. Do not create one monolithic output for an entire Terraform root and do not expose complete provider resource objects.

Examples:

- `isv_virtual_network`: ID, name, resource group, location, and address spaces.
- `isv_workload_subnet`: ID, name, and address prefixes.
- `nva_load_balancer`: ID and frontend IP.
- `nva_virtual_machines`: map keyed by NVA name with ID, zone, NIC ID, and private IP.
- `isv_bastion`: ID, name, and DNS name.
- `customer_virtual_hub`: ID, name, address prefix, and default route-table ID.
- `customer_virtual_hub_firewall`: nullable firewall, policy, address, and routing-intent details.
- `customer_workload_connection`: ID.
- `isv_route_table`: ID and route details.
- `isv_hub_connection`: ID, associated route-table ID, and static-route details.

Only outputs needed by another root or by verification scripts are required. Do not output credentials or private keys.

## 8. Terraform implementation requirements

- Use a pinned Terraform version and pinned `azurerm` provider; commit dependency lock files.
- Use `azurerm_virtual_hub_connection` for static routes, propagation, association, and `static_vnet_local_route_override_criteria`. AzAPI is not required.
- Authenticate locally with Azure CLI.
- Require subscription IDs, region, CIDRs, fixed IPs, VM size, NVA count,
  optional zones, and admin username as inputs.
- Derive resource names from the optional `isv_prefix` and `customer_prefix` variables, whose defaults group the demo resources together in the portal.
- Put deployment-specific values in `${DEPLOYMENT_NAME}.tfvars`; keep the two
  naming-prefix defaults in `variables.tf`.
- Keep cross-input consistency checks in `validations.tf`.
- Use SSH public-key authentication and disable passwords.
- Assign one Standard public IP to each NVA NIC for explicit outbound
  connectivity; do not allow direct internet ingress.
- Enable NIC IP forwarding on NVA NICs.
- Deploy one to three NVA VMs, either in matching distinct availability zones
  or non-zonally; no availability-set fallback.
- Use Bash scripts compatible with WSL; no PowerShell scripts.
- Add comments only for non-obvious routing behavior.
- Add explicit dependencies only when Azure control-plane ordering requires them.
- Allow extended timeouts for Virtual WAN convergence.
- Do not add tags or CI configuration.

AzureRM reference: [azurerm_virtual_hub_connection](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_hub_connection)

## 9. NVA configuration

Cloud-init must:

1. Enable IPv4 forwarding persistently.
2. Allow forwarding only between the configured customer and ISV traffic CIDRs.
3. Avoid masquerade/SNAT between those prefixes.
4. Start a systemd socket/service for the load-balancer TCP health probe.
5. Expose forwarding counters for verification.
6. Fail provisioning if forwarding or the health probe cannot start.

NSGs must allow:

- the Azure Load Balancer health probe to the probe port;
- test traffic between the customer and ISV workload CIDRs;
- SSH from the local `AzureBastionSubnet`;
- no direct internet ingress to VMs.

## 10. Implementation sequence

1. Deploy `01-isv-core` and verify all NVA backends are healthy.
2. Deploy `02-customer-core` and wait for the virtual hub and workload connection to succeed.
3. Deploy `03-isv-routing` to establish the return path before exposing connectivity.
4. Deploy `04-customer-connection` and wait for route convergence.
5. Follow `docs/verification.md` and run the Bash verification scripts.

## 11. Verification

`docs/verification.md` provides an interactive walkthrough for:

1. Connecting from WSL through Bastion Standard with native SSH.
2. Inspecting hub and NIC effective routes.
3. Starting NVA counters or packet capture.
4. Testing ICMP and TCP traffic initiated from both workload VMs.
5. Confirming original source addresses are preserved.
6. Stopping one NVA, waiting for probe convergence, and repeating the tests.
7. Running negative tests by removing the ISV UDR or customer-side connection.

Automated checks:

| Test | Expected result |
|---|---|
| Terraform format and validation | Pass in all roots |
| Propagated hub route | ISV workload prefix uses the ISV connection |
| Customer-to-ISV ICMP and TCP | Pass through one NVA |
| ISV-to-customer ICMP and TCP | Pass through one NVA |
| Destination-observed source IP | Original workload VM address |
| Stop either NVA | Traffic continues through the healthy NVA |
| Remove ISV UDR | Negative control shows return-path bypass or failure |
| Remove customer-side connection | Cross-VNet traffic fails |

Correlate test timestamps with NVA counters or packet captures. Effective-route output alone does not prove NVA traversal.

## 12. Teardown

Destroy in this order:

1. `04-customer-connection`
2. `03-isv-routing`
3. `02-customer-core`
4. `01-isv-core`

Verify that none of the six resource groups, Bastion public IPs, disks, or other billable resources remain.

## 13. Definition of done

- All four Terraform roots apply and destroy in the documented order using their respective owner credentials.
- Both traffic directions are proven to traverse an NVA without SNAT.
- Traffic continues after either NVA is stopped.
- Bastion native SSH access works from WSL.
- The diagram matches deployed CIDRs, routes, and ownership.
- The README and verification guide cover deployment, validation, troubleshooting, and cleanup without duplicating implementation details.

## References

- [Static routes in Virtual WAN](https://learn.microsoft.com/azure/virtual-wan/static-routes)
- [Virtual hub routing](https://learn.microsoft.com/azure/virtual-wan/about-virtual-hub-routing)
- [Connect a VNet to a Virtual WAN hub](https://learn.microsoft.com/azure/virtual-wan/howto-connect-vnet-hub)
- [Azure Load Balancer HA Ports](https://learn.microsoft.com/azure/load-balancer/load-balancer-ha-ports-overview)
- [Azure Bastion overview](https://learn.microsoft.com/azure/bastion/bastion-overview)
- [Bastion native Linux client](https://learn.microsoft.com/azure/bastion/connect-vm-native-client-linux)
- [AzureRM virtual hub connection](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_hub_connection)
