# Architecture and routing design

This disposable demo is designed to forward traffic between customer and ISV workloads through ISV-managed Linux NVAs without source NAT (SNAT). [README.md](README.md) covers deployment and teardown; [verification.md](docs/verification.md) establishes what the deployed path actually does. Connectivity alone is not proof of NVA traversal.

## Scope and ownership

The topology uses one region, one Standard Virtual WAN hub, two workload VNets, one to three NVAs, and a Bastion host for each VNet. Azure Firewall is optional. It is not a production firewall, HA appliance, or cross-tenant automation solution. VPN, ExpressRoute, indirect spokes, multi-hub routing, IPv6, and stateful firewall failover are out of scope.

| Terraform root | Owner | Resources |
|---|---|---|
| `01-isv-core` | ISV | ISV network, NVA cluster, test workload, Bastion |
| `02-customer-core` | Customer | Virtual WAN/hub, customer network, test workload, Bastion, optional Firewall and logs |
| `03-isv-routing` | ISV | Customer return-path UDR and ISV workload-subnet association |
| `04-customer-connection` | Customer | ISV hub connection and connection-level static route |

Each core root creates three resource groups: network, workload, and Bastion. NSGs live in the network groups and are associated with subnets. The ISV UDR also lives in the ISV network group. Customer-side routing lives on hub connections and hub-managed route tables.

Each root owns separate local state. No resource is managed by two roots, and roots exchange explicit input/output values rather than reading each other's state. Keep state until teardown is confirmed; local state is not a shared production backend.

## Components

| Component | Implementation |
|---|---|
| NVA VMs, NICs, public IPs, internal load balancer | [linux-nva-cluster](modules/linux-nva-cluster/) |
| Workload VMs and cloud-init checks | [linux-test-vm](modules/linux-test-vm/) |
| Linux forwarding and probe responder | [nva/](nva/) |
| Common VM testing packages | [testing-tools.yaml](cloud-init/testing-tools.yaml) |
| Output-to-shell variable loading | [environment.sh](environment.sh) |
| Effective-route troubleshooting | [show-effective-routes.sh](scripts/show-effective-routes.sh) |
| Reference topology | [architecture.svg](diagrams/architecture.svg), [architecture.drawio](diagrams/architecture.drawio) |

The diagram labels workload VMs with the demo's static private IPs; NVA private IPs are dynamically assigned and shown only as examples. Azure service icons are embedded from the [official Microsoft icon set](https://learn.microsoft.com/azure/architecture/icons/), under its architecture-diagram usage terms.

Terraform and AzureRM versions are pinned in each root's `providers.tf`. Reusable modules have no backend configuration. The implementation history remains in [implementation-log.md](docs/implementation-log.md).

## Address and naming contracts

The sanitized `demo.tfvars` files provide this reference address plan:

| Network or endpoint | Value |
|---|---|
| Virtual hub | `10.0.0.0/23` |
| Customer VNet | `10.10.0.0/16` |
| Customer workload / Bastion subnets | `10.10.1.0/24`, `10.10.255.0/26` |
| Customer workload VM | `10.10.1.10` |
| ISV VNet | `192.168.0.0/16` |
| ISV NVA / workload / Bastion subnets | `192.168.0.0/24`, `192.168.1.0/24`, `192.168.255.0/26` |
| NVA load-balancer frontend | `192.168.0.10` |
| ISV workload VM | `192.168.1.4` |

CIDRs and fixed IPs are explicit inputs. Terraform checks local containment, overlap, and reserved-address constraints; the operator must also check connected VNet and branch ranges.

`isv_prefix` must match in roots 01 and 03; `customer_prefix` must match in roots 02 and 04. Terraform defaults are `fd-isv` and `fd-customer`; the example overrides them with `demo-isv` and `demo-customer`. Names add fixed role/type suffixes. `AzureBastionSubnet` keeps its Azure-required name.

The ISV traffic prefix is not necessarily the physical workload subnet:

- Root 01's `isv_forwarding_address_prefix` defaults to the workload subnet when unset.
- Roots 02 and 04 use `isv_workload_address_prefix` as the permitted/routed destination range.
- The example uses the full ISV VNet for both. Keep those ranges consistent.

Additional workload subnets need suitable NSGs and their own return-path UDR association. Do not attach that UDR to NVA or Bastion subnets. Omitting a UDR is not an ingress filter: a broad hub route can still affect infrastructure addresses.

## Routing contracts

### Hub-to-ISV route

Root 04 creates a connection with:

- A static route for `isv_workload_address_prefix`.
- The NVA load-balancer frontend as next-hop IP.
- Static-route propagation enabled.
- A caller-supplied `associated_route_table_id`; the example uses the hub's `defaultRouteTable`.
- `static_vnet_local_route_override_criteria = "Contains"`, corresponding to **Bypass Next Hop IP for workloads within this VNet = No**.

Root 04 does not expose propagated route-table IDs or labels and does not configure an explicit propagation block. Root 02 associates the customer workload connection with `defaultRouteTable`. Custom hub tables are not provisioned by this demo.

Azure configures the bypass setting at connection creation. Changing it can require connection replacement and interrupt connectivity; inspect the plan before applying.

### ISV return path

Root 03 associates a UDR with the ISV workload subnet:

| Destination | Next-hop type | Next-hop IP |
|---|---|---|
| Customer VNet CIDR | `VirtualAppliance` | NVA load-balancer frontend |

The NVA subnet has no such UDR. After forwarding, an NVA uses its hub-learned customer route rather than sending traffic back to the load balancer.

### Optional Firewall and Routing Intent

| Deploy Firewall | Route private traffic | Hub configuration |
|---|---|---|
| `false` | `false` | No Firewall or Routing Intent |
| `true` | `false` | Firewall with Internet Traffic Routing Intent |
| `true` | `true` | Firewall with Internet and Private Traffic Routing Intent |

The variables are `virtual_hub_deploy_firewall` and `virtual_hub_route_private_traffic`. Private routing requires Firewall; Terraform rejects `false`/`true`. Both inputs default to `false`, while the checked-in example sets both to `true`.

Only the customer workload connection enables Internet Security. The ISV connection does not, avoiding an advertised hub default route on the NVA connection.

**Routing limitation:** Microsoft documents that Routing Intent can override the bypass setting when static routes are propagated. Traffic for the connected VNet may then bypass the spoke next-hop IP even with `Contains`. Do not assume an NVA path solely from that setting or from a successful TCP connection. Inspect NVA ingress/egress packet captures for the chosen mode; use effective-route diagnostics when troubleshooting.

The demo Firewall policy permits traffic between configured customer/ISV prefixes, permits HTTP/HTTPS except `www.facebook.com`, and otherwise uses default deny. It is not a production policy and has no separate infrastructure exclusions. Diagnostics send `AZFWNetworkRule` and `AZFWFlowTrace` to Log Analytics; the verification guide queries only network-rule logs. Optional Flow Trace logging requires the [additional subscription feature](https://learn.microsoft.com/azure/firewall/monitor-firewall-reference#flow-trace).

## NVA forwarding and availability

Each NVA has one IP-forwarding NIC and belongs to a Standard internal load-balancer backend pool. One HA Ports rule uses protocol `All`, ports `0`, Floating IP, and a TCP probe every five seconds with two probes configured. The frontend IP is a next hop, not a workload endpoint or configured NVA loopback address.

Cloud-init enables IPv4 forwarding, disables reverse-path filtering, and installs nftables forwarding rules for the two configured traffic prefixes. Other forwarded traffic is dropped; there is no masquerade/SNAT rule. Named counters track each direction. A systemd socket/service answers the health probe. VM extensions wait for cloud-init and validate required tools, forwarding, counters, and the probe responder.

Terraform defaults to two NVAs in distinct zones. The example instead uses one non-zonal NVA. `nva_vm_count` accepts 1 through 3; non-null `nva_zones` must contain one distinct zone per NVA. Non-zonal VMs do not provide zone-failure isolation. Instance redundancy requires at least two healthy NVAs; one NVA cannot provide it.

## Management and security boundaries

Each VNet has Bastion Standard with native-client tunneling and a Standard public IP. Workload VMs have private IPs only. Each NVA also has a Standard public IP for outbound connectivity; this is not a public SSH access path. Use Bastion and SSH keys for management.

Subnet NSGs explicitly allow Bastion SSH, workload test traffic, and NVA health probes as applicable. Their default rules also apply; these explicit allows are not an exclusive management-access policy. The Linux rules restrict forwarding, not every connection addressed to the NVA itself.

## Intended paths and proof

For a mode that honors the connection next hop:

- **Customer to ISV:** customer workload -> hub -> ISV connection static route -> NVA load balancer -> healthy NVA -> ISV workload.
- **ISV to customer:** ISV workload UDR -> NVA load balancer -> healthy NVA -> hub -> customer workload.

Firewall-enabled modes may add Firewall traversal or change the spoke path. The [verification runbook](docs/verification.md) distinguishes intended behavior from measured results. The walkthrough demonstrates one customer-initiated TCP connection: its requests and replies must traverse the NVA path, and the receiver must observe the original source address. This is not a separate test of ISV-initiated connections. A mode that bypasses the NVA in either traffic direction has not proven the intended design.

## References

- [Virtual WAN static routes](https://learn.microsoft.com/azure/virtual-wan/static-routes)
- [Hub association and propagation](https://learn.microsoft.com/azure/virtual-wan/about-virtual-hub-routing)
- [Bypass next-hop semantics](https://learn.microsoft.com/azure/virtual-wan/howto-connect-vnet-hub#understanding-bypass-next-hop-ip-for-workloads-within-this-vnet)
- [Routing Intent limitations](https://learn.microsoft.com/azure/virtual-wan/how-to-routing-policies#known-limitations)
- [Load Balancer HA Ports](https://learn.microsoft.com/azure/load-balancer/load-balancer-ha-ports-overview)
- [Bastion native Linux client](https://learn.microsoft.com/azure/bastion/connect-vm-native-client-linux)
- [Firewall Flow Trace prerequisites](https://learn.microsoft.com/azure/firewall/monitor-firewall-reference#flow-trace)
