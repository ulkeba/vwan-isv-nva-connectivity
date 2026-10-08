# Implementation Log

This file is the durable, session-independent record of implementation decisions, progress, validation evidence, and deployment handoff for the Azure Virtual WAN / ISV NVA demo.

It intentionally excludes credentials, access tokens, private keys, Terraform state contents, and other sensitive values.

## Status

| Area | Status | Evidence |
|---|---|---|
| Repository foundations | Complete | Terraform 1.16.3 installed after SHA-256 verification; SSH key generated; ignore rules and persistent tracking added |
| Reusable VM modules | Complete | Integrated into both core roots; format, validation, and plans pass |
| NVA configuration | Complete | Cloud-init renders; shell/static checks and ISV core plan pass |
| ISV core | Complete | Valid plan: 26 resources to create |
| Customer core | Complete | Valid plan: 14 graph objects to create, including input validation |
| ISV routing | Complete | Valid plan: 3 resources to create |
| Customer connection | Complete | Valid plan: 2 graph objects to create, including input validation |
| Operations scripts | Complete | Bash syntax, executable help paths, and argument error paths pass |
| Documentation and diagrams | Complete | Draw.io and SVG parse as XML; README and verification guide added |
| Local validation | Complete | All roots validate and plan; negative validation tests reject invalid inputs |
| Deployment naming | Complete | Matching tfvars, workspace, and evidence names are driven by `DEPLOYMENT_NAME` |
| Azure deployment | Destroyed | Secured-hub deployment tested end to end and all four roots destroyed in reverse dependency order |
| Smoke checks and handoff | Complete | Routing, firewall policy, bidirectional no-SNAT traffic, NVA failover, drift, and cleanup verified |
| PrivateTraffic experiment | Live, expected partial deployment | Routing Intent rejects the ISV connection's NVA static route; `fd-ri-*` resources remain for inspection |

## Decisions

### D-001: Use one subscription with ownership separated by Terraform roots

- **Status:** Accepted
- **Decision:** Deploy the ISV and customer resources into separate resource groups in the active Azure subscription. Each numbered Terraform root has its own provider configuration and local state.
- **Rationale:** This preserves lifecycle and state ownership boundaries while matching the available demo environment.
- **Alternative considered:** Separate ISV and customer subscriptions. This better models organizational separation but is not required for this demo.
- **Consequence:** Subscription-level isolation is not demonstrated. Cross-tenant authorization remains out of scope.

### D-002: Use separate local Terraform state files

- **Status:** Accepted
- **Decision:** Use the local backend in each numbered root. State and plan files are excluded from version control.
- **Rationale:** The user selected local state for this disposable, single-operator demo.
- **Alternative considered:** Four keys in an Azure Storage backend.
- **Consequence:** The local state directories must be retained until the environment is destroyed. The solution is not suitable for concurrent operators.

### D-003: Deploy in Sweden Central

- **Status:** Accepted
- **Decision:** Use `swedencentral`, with the NVA VMs in availability zones 1 and 2.
- **Rationale:** The active subscription reports Virtual WAN, Virtual Hub, Bastion, and Load Balancer availability; `Standard_B2s` supports zones 1, 2, and 3; regional and BS-family vCPU quotas are sufficient.
- **Alternative considered:** West Europe, North Europe, and Germany West Central.
- **Consequence:** A final SKU/quota check is still performed immediately before deployment because Azure capacity and restrictions can change.

### D-004: Pin Terraform and AzureRM

- **Status:** Accepted
- **Decision:** Pin Terraform CLI `1.16.3` and AzureRM provider `5.6.0`, with provider dependency lock files committed for all roots.
- **Rationale:** These were the current releases reported by HashiCorp release metadata and the Terraform MCP server at implementation time. Exact pins make the demo reproducible.
- **Consequence:** Upgrades are deliberate and require revalidation of all roots.

### D-005: Use a dedicated local SSH key

- **Status:** Accepted
- **Decision:** Generate an Ed25519 key pair at `~/.ssh/fd-fwaas-demo`; Terraform receives only the public key.
- **Rationale:** No SSH key existed in the environment, and password authentication is prohibited by the design.
- **Consequence:** The private key is an operator prerequisite for Bastion native-client access and is never copied into this repository.

### D-006: Use MCP for design-time checks and CLI/Terraform for execution

- **Status:** Accepted
- **Decision:** Use the Azure and HashiCorp Terraform MCP servers for authoritative schema and best-practice checks. Use Terraform and Azure CLI for local validation, live preflight, deployment, readiness, routing, and data-plane verification.
- **Rationale:** This combines current provider documentation with evidence from the actual subscription.
- **Consequence:** Deployment does not depend on MCP server availability after configuration has been validated.

### D-007: Leave the deployed resources running

- **Status:** Accepted
- **Decision:** Apply all four roots and run non-destructive smoke checks, but leave resources in place for interactive failover and negative-control verification.
- **Rationale:** The user requested a deployed handoff.
- **Consequence:** Bastion Standard and Virtual WAN resources continue to incur charges until the documented teardown is run.

### D-008: Associate NSGs at subnet scope

- **Status:** Accepted
- **Decision:** Associate the workload and NVA NSGs with their subnets. Pass `null` for optional module-level NIC NSG associations.
- **Rationale:** Subnet association applies the intended policy consistently and avoids plan-time cardinality depending on a resource-computed NSG ID.
- **Consequence:** NIC modules retain optional NSG support for reuse, but this deployment uses subnet-level enforcement.

### D-009: Use blocking Terraform preconditions for cross-input checks

- **Status:** Accepted
- **Decision:** Implement cross-variable network and resource-ID checks as `terraform_data` lifecycle preconditions.
- **Rationale:** Terraform `check` assertions warn but do not reject an invalid plan. The design requires invalid address and onboarding contracts to fail visibly.
- **Consequence:** Each root includes one local validation object in its plan where cross-input checks are required.

### D-010: Use a blocking systemd socket responder

- **Status:** Accepted
- **Decision:** Let systemd pass a blocking listener to the long-running Python health responder.
- **Rationale:** `NonBlocking=true` caused the responder to fail with `BlockingIOError` after an accepted connection when no second connection was queued. Removing it keeps the service active across repeated Azure Load Balancer probes.
- **Consequence:** Both deployed backends reached 100% `DipAvailability` after replacement and probe convergence.

### D-011: Persist verification evidence by deployment layer

- **Status:** Accepted
- **Decision:** Each verification run captures one `.json` Terraform output file for each of the four deployment layers. The committed root `environment.sh` loads resource identifiers, names, addresses, and prefixes from those files with `jq`. NVA values are selected by availability zone from the structured VM output.
- **Rationale:** Operators can inspect four explicit capture commands, source the environment once in an ongoing shell, and paste the remaining linear commands without replacing placeholders or hard-coding derived resource names.
- **Consequence:** `jq` is a verification prerequisite. Verification artifacts
  are stored under the ignored `evidence_${DEPLOYMENT_NAME}/` directory and
  must be regenerated and re-sourced after infrastructure changes.

### D-012: Give each NVA an outbound public IP

- **Status:** Accepted
- **Decision:** Attach a zonal Standard public IP to each NVA NIC.
- **Rationale:** Standard internal Load Balancers do not provide outbound connectivity to backend VMs.
- **Consequence:** The NVAs have explicit outbound access; the subnet NSG still denies unsolicited internet ingress.

### D-013: Provision verification tools with cloud-init

- **Status:** Accepted
- **Decision:** Install `netcat-openbsd`, `net-tools`, `tcpdump`, `iputils-ping`, and `python3` on every demo VM from one shared package manifest.
- **Rationale:** Automated and interactive verification must not depend on manual package installation.
- **Consequence:** Applying the new `custom_data` replaces both NVAs and both workload VMs.

### D-014: Destroy the demo deployment

- **Status:** Accepted
- **Decision:** Destroy all four Terraform roots in reverse dependency order.
- **Rationale:** The user requested complete removal of the demo deployment.
- **Consequence:** All four Terraform states are empty and all six demo resource groups have been deleted.

### D-015: Add optional customer internet filtering

- **Status:** Accepted
- **Decision:** Let `02-customer-core` optionally deploy Azure Firewall and Internet Traffic routing intent for the customer workload connection only.
- **Rationale:** Demonstrate a secured hub with minimal code impact while preserving the existing symmetric private NVA path.
- **Consequence:** The customer learns `0.0.0.0/0` through Azure Firewall; all private route destinations and NVA next hops remain unchanged. Azure Firewall adds significant hourly cost.

### D-016: Test PrivateTraffic Routing Intent without a workaround

- **Status:** Accepted and confirmed
- **Decision:** Add a default-off `virtual_hub_route_private_traffic` toggle and test it in isolated `ri` workspaces with `fd-ri-isv` and `fd-ri-customer` prefixes.
- **Rationale:** Confirm whether PrivateTraffic Routing Intent is compatible with the ISV connection's NVA static next hop without changing the established routing design.
- **Consequence:** Azure rejected the ISV connection with `ConnectionRoutingConfigConflictsWithRoutingIntent`. The existing routing block cannot coexist with PrivateTraffic Routing Intent. No workaround was investigated, and the partial `fd-ri-*` deployment remains live.

### D-017: Support configurable and non-zonal NVA placement

- **Status:** Accepted
- **Decision:** Support one to three NVA instances, defaulting to two. Keep `nva_zones = ["1", "2"]` as the zonal default; accept `null` to deploy all NVAs and their Standard public IPs without zone placement.
- **Rationale:** Some target Azure regions do not provide Availability Zones, while other environments still need the existing zonal topology.
- **Consequence:** Non-null zone lists must contain exactly one distinct valid zone per NVA. Non-zonal deployments retain instance redundancy when multiple NVAs are configured but do not provide explicit zone-failure isolation. Dedicated non-zonal environment tfvars are deferred.

### D-018: Use one deployment name across files, state, and evidence

- **Status:** Accepted
- **Decision:** Require `DEPLOYMENT_NAME`, set `TF_WORKSPACE` to the same value,
  and use it for each root's `${DEPLOYMENT_NAME}.tfvars`, shell-local Terraform
  workspace, and `evidence_${DEPLOYMENT_NAME}` directory.
- **Rationale:** One identifier prevents plans, outputs, and evidence from
  silently targeting different deployments.
- **Consequence:** The original `default` states were migrated to
  `swedencentral`, and the original `ri` states were migrated to
  `ri-swedencentral`, in all four roots. The built-in `default` workspaces
  remain empty because Terraform cannot delete them; the old `ri` workspaces
  were deleted after state equivalence checks. `ri-centralus` was already
  correctly named and remains unchanged. Commands no longer mutate shared CLI
  workspace selection with `terraform workspace select`.

### D-019: Use a visually distinct ISV address space

- **Status:** Accepted
- **Decision:** Move every active ISV deployment profile from `10.100.0.0/16` to `192.168.0.0/16`, preserving subnet and host offsets.
- **Rationale:** Customer `10.10` and ISV `10.100` addresses are difficult to distinguish quickly in logs and packet captures.
- **Consequence:** ISV resources, cross-root route destinations, NVA next hops, firewall rules, and verification examples use `192.168`; customer addressing remains on `10.10`. Applying the change to an existing environment requires replacement or recreation of address-dependent resources.

### D-020: Add regional BUC secured-hub profiles

- **Status:** Accepted
- **Decision:** Keep `buc-nori-cin` unchanged and add `buc-nori-wcus` and `buc-nori-gwc` profiles with Azure Firewall, Internet and Private Traffic Routing Intent, one NVA, and non-zonal NVA and workload placement.
- **Rationale:** Provide comparable BUC environments in West Central US and Germany West Central while supporting regions or deployments that do not use Availability Zones.
- **Consequence:** Each new deployment has matching tfvars across all four roots and a shell-local environment file. A single non-zonal NVA cannot demonstrate load-balancer or zone failover. Root 04 no longer supplies an explicit propagated-route-table block, but successful Azure control-plane acceptance and packet-path behavior still require live verification.

### D-021: Align Central India with single-NVA non-zonal placement

- **Status:** Accepted
- **Decision:** Set `buc-nori-cin` to one non-zonal NVA and non-zonal ISV and customer workloads, superseding D-020's requirement to keep its placement unchanged.
- **Rationale:** Use the same VM placement and count across all three BUC profiles.
- **Consequence:** Central India retains its existing region, addresses, names, and unsecured Virtual WAN with Firewall and Routing Intent disabled. Applying the change removes the second NVA and replaces zone-dependent resources as required; the single NVA cannot demonstrate failover.
- **Validation:** Both core roots validate, and isolated refresh-free plans confirm one NVA/backend, omitted NVA VM/public-IP zones, non-zonal workloads, Central India location, and no Firewall or Routing Intent. No resources were deployed.

### D-022: Deploy the three BUC demos in parallel

- **Status:** Completed; all three environments left running
- **Decision:** Use one deployment agent per BUC profile, applying layers 01 through 04 sequentially within each environment. Select state using `TF_WORKSPACE` and reuse the four existing roots after one shared initialization.
- **Rationale:** Deploy independent regional demos concurrently without copying Terraform roots, changing CLI workspace selection, or racing shared initialization.
- **Consequence:** Each agent owns only its environment's resources, workspace, plans, and evidence. Check provisioning and passive health only; leave traffic tests to the user. Retain all resources, including partial deployments on failure, without routing workarounds or automatic cleanup.
- **Preparation:** Registered `Microsoft.OperationalInsights` and `Microsoft.Insights`. Recreated the four missing lock files using pinned AzureRM `5.6.0`, then initialized and validated the shared roots. Target resource groups were absent and managed workspace state was empty before deployment. Preparation logs are in `evidence_buc-demo-preflight/`.
- **Central India result:** Layers 01 through 04 applied successfully (28, 19, 3, and 2 additions; no changes or destruction). All three non-zonal VMs are running with successful cloud-init health extensions; both Standard Bastions support tunneling; the hub is `Succeeded`/`Provisioned` and both connections are `Succeeded`. Passive load-balancer health is 100%, all four drift checks are clean, and `environment.sh` loads the demo IDs successfully. Evidence: `evidence_buc-nori-cin/run-20261004T111042Z-383624/`. No traffic tests were run; resources remain running.
- **Germany West Central result:** Layers 01 through 04 applied successfully (28, 25, 3, and 2 additions; no changes or destruction). Readiness passed for the hub, both connections, both Bastions, all three non-zonal VMs and cloud-init health extensions, Firewall/policy, diagnostics, workspace, and both Routing Intent policies. Passive load-balancer health is 100%. Azure accepted root 04 without an explicit propagated-route-table block and returned `noneRouteTable`/label `none`. Effective hub routes target Firewall for Internet and RFC1918 prefixes; the ISV workload retains its customer-prefix UDR to `192.168.0.10`. Evidence: `evidence_buc-nori-gwc/run-20261004T111031Z-383379/deployment-summary.json`. Connectivity and NVA traversal remain untested; resources remain running.
- **West Central US result:** Layers 01 through 04 applied successfully (28, 25, 3, and 2 additions; no changes or destruction), with clean drift checks for all four roots. All three VMs and health extensions, both Standard Bastions, hub and connections, Firewall/policy, diagnostics, workspace, and both Routing Intent policies are ready. Passive load-balancer health is 100%. Root 04 was accepted with computed propagation `none`; the ISV customer-prefix UDR targets the NVA frontend, while NVA/customer private routes target Firewall. Evidence: `evidence_buc-nori-wcus/run-20261004T111034Z-383488/readiness-summary.json`. No traffic tests were run; resources remain running.
- **Demo handoff:** In a separate repository-root shell for each environment, source its `env_<DEPLOYMENT_NAME>.sh` followed by `environment.sh`. Use section 6 of `docs/verification.md` for interactive captures without stopping the single NVA. Failover and destructive negative controls are excluded. Captured route state does not prove connectivity or NVA traversal, and Firewall log ingestion may lag.

### D-023: Support sourcing the environment in Bash and zsh

- **Status:** Accepted
- **Decision:** Replace Bash-only NVA loading and variable-assignment constructs with Bash/zsh-compatible equivalents; reject unsupported shells explicitly.
- **Rationale:** Sourcing ignores the shebang. zsh reported `command not found: mapfile` and `bad substitution` for the Bash array-index expansion.
- **Consequence:** Preserve sorted NVA arrays, count, numbered compatibility variables, and repeated-source cleanup without changing shell options or deployed resources.
- **Validation:** Reproduced the original errors in zsh; both Bash and zsh now load all three demo environments and pass one-/two-/three-NVA regression checks, repeated sourcing, exported-variable checks, unchanged-shell-option checks, and invalid-input rejection. Unsupported shells fail with an actionable message. No Azure operations were performed.

### D-024: Keep the PoC diagram focused on the data path

- **Status:** Accepted
- **Decision:** Remove Bastion/SSH elements from both diagram formats, show NVA 2 and its connections dashed as optional, and replace NVA zone/forwarding/SNAT detail labels with example VM IPs.
- **Rationale:** Management access is deployed but is not relevant to the PoC diagram; the current demos use one NVA.
- **Consequence:** No deployed resources change. NVA IPs are explicitly illustrative because backend NICs use dynamic addressing; actual addresses remain available in Terraform outputs.
- **Validation:** Both formats parse as XML; no Bastion elements or dangling connections remain; NVA 2 and its branches are dashed; NVA labels contain IPs instead of zone/forwarding/SNAT details. The SVG was visually reviewed.

### D-025: Broaden BUC ISV routing and workload policy to the full VNet

- **Status:** Superseded by D-026; original proposal was validated but never applied
- **Decision:** Use `192.168.0.0/16` for ISV routing and workload forwarding in the three BUC profiles, while excluding the NVA `192.168.0.0/24` and Bastion `192.168.255.0/26` subnets from customer access in both directions.
- **Rationale:** Permit workload traffic across the ISV VNet without exposing management infrastructure or changing the physical workload subnet.
- **Consequence:** Exclusions precede broader NSG, nftables, and Firewall allows. Older profiles retain workload-subnet forwarding and no new exclusions. Return UDRs remain on workload subnets only; future workload subnets need appropriate UDR/NSG configuration. Changing NVA cloud-init is expected to replace each single NVA, so live application requires separate approval.
- **Validation:** All four roots validate and nine saved live-workspace plans succeed. Plan/render checks cover workload and infrastructure CIDR boundaries, deny precedence, Bastion SSH and LB probe exceptions, unchanged subnet layout, and preserved web rules. Eight invalid CIDR/containment cases fail explicitly. Legacy cloud-init remains byte-for-byte identical and legacy forwarding/customer defaults produce zero-change plans. All twelve BUC state files and older profile inputs remain unchanged.
- **Planned impact:** Each environment replaces one NVA VM and its health extension and updates the NVA NSG, customer NSG, and ISV connection in place. WCUS/GWC additionally update the Firewall rule collection group. No workload VM, subnet, Bastion, Firewall appliance, or Routing Intent changes are planned. Saved plans, readable logs, JSON, and summaries are under each `evidence_<profile>/full-isv-policy-20261006/` directory. No apply or live traffic tests were run.

### D-026: Simplify the full-VNet PoC policy

- **Status:** Implemented and validated; no live apply
- **Decision:** Retain full `/16` BUC routing and forwarding, but remove the infrastructure CIDR parameters, extra NSG/Firewall denies, and nftables exclusions introduced by D-025.
- **Rationale:** The exclusions were optional access-policy hardening, not a requirement for routing or forwarding. Keep the PoC simple and reuse its existing allow rules.
- **Consequence:** Older profiles retain their existing defaults; NVA/Bastion subnets still receive no return-path UDR. That absence does not filter ingress from the hub: aggregate routes can affect traffic addressed to private infrastructure IPs, separately from normal Bastion public access/local SSH. NVA replacement remains expected when applying the broader forwarding prefix. D-025 saved plans are superseded; use the newly generated simplified plans.
- **Validation:** All four roots validate and nine new saved plans succeed. Existing NSG/Firewall rule counts and Bastion/probe rules are preserved; nftables renders only its original two forwarding allows with the broader CIDR. The original cloud-init template is restored exactly; legacy defaults give zero-change plans. All BUC state files and older profile inputs remain unchanged. Current plans and summaries are in `evidence_<profile>/full-isv-policy-simple-20261006/`. No apply or traffic tests were run.

## Implementation checklist

- [x] Establish repository foundations and generate the SSH key.
- [x] Implement and validate reusable VM modules.
- [x] Implement and validate NVA forwarding and probe configuration.
- [x] Implement and validate `01-isv-core`.
- [x] Implement and validate `02-customer-core`.
- [x] Implement and validate `03-isv-routing`.
- [x] Implement and validate `04-customer-connection`.
- [x] Implement and validate operations scripts.
- [x] Complete README, verification guide, and architecture diagrams.
- [x] Run local formatting, initialization, validation, and plan checks.
- [x] Apply ISV core and verify both NVA backends.
- [x] Apply customer core and wait for Virtual WAN convergence.
- [x] Apply ISV routing, then the customer connection.
- [x] Run non-destructive smoke checks.
- [x] Record deployment identifiers, deviations, risks, and cleanup handoff.

## Validation evidence

- Terraform `1.16.3` archive downloaded from HashiCorp Releases and verified against the published SHA-256 checksum before installation to `~/.local/bin/terraform`.
- The current runbook expects a dedicated Ed25519 key at `~/.ssh/fd-fwaas-demo`; operators generate it before deployment.
- Active Azure subscription and identity were checked before implementation. Required Compute, Network, and Storage providers are registered.
- Sweden Central preflight found `Standard_B2s` available in zones 1, 2, and 3, with 100 regional vCPUs and 100 BS-family vCPUs permitted at the time of the check.
- `bash -n` passes for all three operations scripts; each script is executable and its `--help` path succeeds.
- `diagrams/architecture.drawio` and `diagrams/architecture.svg` parse successfully as XML.
- `04-customer-connection` and `03-isv-routing` initialize and validate successfully with AzureRM `5.6.0`.
- `terraform fmt -recursive` and `terraform validate` pass for all four roots.
- Shared diagnostic cloud-init renders with the required five-package set on all four VMs. Refresh-free plans show only the expected four VM replacements and cloud-init health-extension changes.
- Full, refresh-free plans succeed: ISV core 26 resources, customer core 14 graph objects, ISV routing 3 resources, and customer connection 2 graph objects. The customer counts include a local `terraform_data` validation object rather than an additional Azure resource.
- Targeted negative plans prove that a `/27` Bastion subnet and a malformed Virtual Hub resource ID fail with blocking precondition errors.
- Independent implementation review found no blockers in the Virtual WAN static-route behavior, `Contains` override semantics, HA Ports/Floating IP configuration, state ownership, or NVA subnet routing. Review findings about blocking validations, nftables reload, TCP observer use, ICMP handling, and reserved frontend addresses were fixed before deployment.
- ISV core applied 26 resources. The first live health check exposed a nonblocking systemd listener bug; the two immutable NVA VMs and their extensions were replaced with the corrected cloud-init. No Bastion or unrelated resource was replaced.
- Both NVA VMs report successful provisioning, IPv4 forwarding enabled, active health socket/service, and the expected two nftables forwarding rules without SNAT.
- Azure Monitor `DipAvailability` reached 100% for both NVA backend IPs after probe convergence.
- Customer core applied 14 graph objects. The Virtual Hub reports `Succeeded` and routing state `Provisioned`; the customer workload connection reports `Succeeded`.
- ISV routing applied the `10.10.0.0/16` UDR to the ISV workload subnet with next hop `10.100.0.10`.
- Customer onboarding applied the ISV hub connection with static `10.100.1.0/24` routing, static-route propagation enabled, default-table association/propagation, and `Contains` local-route override.
- Effective hub routes include the customer VNet, ISV VNet, and propagated ISV workload `/24`. The ISV workload NIC has an active virtual-appliance route to `10.100.0.10`; the NVA NIC has an active virtual-hub route to the customer prefix.
- Customer-to-ISV ICMP and TCP passed. The destination observed source `10.10.1.10`.
- ISV-to-customer ICMP and TCP passed. The destination observed source `10.100.1.4`.
- Post-test counters were nonzero on both NVAs in both directions, proving NVA traversal.
- Post-deployment `terraform plan -detailed-exitcode` returned exit code 0 for all four roots: no drift.
- The verification guide was simplified into linear copy-and-paste Bash blocks. It writes four per-layer Terraform JSON snapshots, sources deployment values from the committed `environment.sh` using `jq`, and captures Azure status, routes, counters, and connectivity evidence.
- The simplified workflow was validated against the deployed environment: all four JSON captures are valid, all derived values are non-empty, NVA name-keyed lookups resolve correctly, Azure hub and connection state checks pass, every Bash block passes `bash -n`, and no angle-bracket placeholders or inline control structures remain.
- Azure CLI commands that identify resources with full `--ids` omit the redundant `--subscription` option. Subscription selection remains only on account- or name-based commands such as Bastion operations.
- The verification guide includes an interactive packet-observation procedure: ensure NVA 1 is running, stop NVA 2, use direct Bastion SSH sessions, capture NVA 1 forwarding with `tcpdump`, exchange a raw TCP message on port 2000 between customer and ISV workloads, verify preserved source/destination addresses, and explicitly restore NVA 2.
- The optional secured-hub implementation was deployed with `virtual_hub_deploy_firewall = true`. Terraform applied 33 ISV-core, 23 customer-core, 3 ISV-routing, and 2 customer-connection objects.
- The Virtual Hub reached `Succeeded` / `Provisioned`; the Azure Firewall, InternetTraffic routing intent, and both hub connections reached `Succeeded`.
- Internet Security was enabled only on the customer workload connection. The ISV connection remained disabled.
- Effective routes proved that the customer default route targets Azure Firewall, customer `10.100.1.0/24` remains on the ISV connection, ISV `10.10.0.0/16` remains an active UDR to `10.100.0.10`, and the ISV default route remains direct Internet.
- Customer-to-ISV and ISV-to-customer ICMP/TCP passed with destination-observed original source addresses. NVA counters increased in both directions.
- Customer access to an allowed HTTPS destination succeeded, while `https://www.facebook.com` was blocked by the firewall policy.
- With NVA 1 stopped, both traffic directions and source preservation continued through NVA 2. NVA 2 counters increased from 12 to 28 packets in each direction; NVA 1 was restored before teardown.
- Post-deployment Terraform plans reported no changes for all four roots.
- Teardown destroyed all 61 managed graph objects in reverse order. All four Terraform states contain zero resources, all six demo resource groups are absent, and no matching Azure resources remain.
- Complete command, JSON, route, counter, connectivity, firewall, drift, and cleanup evidence is retained in the ignored local `evidence/` directory with SHA-256 checksums.

### PrivateTraffic Routing Intent experiment

The experiment used separate `ri` Terraform workspaces and the isolated
`evidence_ri/` directory. All existing `demo.tfvars` files remained unchanged.
Roots 01, 02, and 03 applied successfully. Azure rejected root 04 when it tried
to create the ISV connection with the existing static NVA route:

```text
ConnectionRoutingConfigConflictsWithRoutingIntent:
Routing configuration for Connection .../fd-ri-customer-network-isv-conn
conflicts with Routing Intent .../fd-ri-customer-network-internet-routing-intent.
Leave Routing configuration empty to auto-populate.
```

The live customer connection was automatically changed to propagate to
`noneRouteTable`, and the hub's effective private route points to Azure
Firewall:

```text
"addressPrefixes": ["10.0.0.0/8"]
"nextHopType": "Azure Firewall"
"nextHops": [".../azureFirewalls/fd-ri-customer-network-fw"]
"id": ".../hubRouteTables/noneRouteTable"
```

Both TCP tests timed out. The customer-to-ISV direction never reached either
NVA, while the ISV-to-customer attempt reached the NVAs through the unchanged
UDR but had no working return path:

```text
Customer to ISV:
4 packets transmitted, 0 received, 100% packet loss
TimeoutError: timed out

NVA 1:
counter customer_to_isv
packets 0 bytes 0
counter isv_to_customer
packets 7 bytes 420

NVA 2:
counter customer_to_isv
packets 0 bytes 0
counter isv_to_customer
packets 4 bytes 336
```

This confirms the reported behavior: PrivateTraffic Routing Intent prevents
the existing symmetric spoke-NVA routing design. Allowed HTTPS still succeeds,
and `www.facebook.com` remains blocked. Roots 01 and 03 are drift-free. Root 02
shows the Routing Intent-managed `noneRouteTable` propagation change, and root
04 retains the expected uncreated connection.

## Deployment handoff

### Active PrivateTraffic experiment

The `fd-ri-*` resources remain deployed for inspection. Their state is in the
`ri` workspace under each root; do not use the default workspace, which belongs
to the separate manual `fd-*` deployment.

The ISV core, customer core, and ISV UDR are live. The ISV hub connection is
intentionally absent because Azure rejected its NVA routing configuration.
Evidence is retained in `evidence_ri/`.

Future teardown must select the isolated workspace metadata and use
`demo-ri.tfvars`, in reverse order:

```bash
TF_DATA_DIR="$PWD/04-customer-connection/.terraform/ri-data" terraform -chdir=04-customer-connection destroy -input=false -var-file=demo-ri.tfvars
TF_DATA_DIR="$PWD/03-isv-routing/.terraform/ri-data" terraform -chdir=03-isv-routing destroy -input=false -var-file=demo-ri.tfvars
TF_DATA_DIR="$PWD/02-customer-core/.terraform/ri-data" terraform -chdir=02-customer-core destroy -input=false -var-file=demo-ri.tfvars
TF_DATA_DIR="$PWD/01-isv-core/.terraform/ri-data" terraform -chdir=01-isv-core destroy -input=false -var-file=demo-ri.tfvars
```

### Archived deployment

The original verification deployment was destroyed after evidence capture. Its
historical Azure identifiers remain only in the separately retained evidence
archive; current deployments use the prefix-derived names documented above.

### Remaining interactive verification

No resources remain deployed. The automated NVA 1 failover test passed. The
manual packet-capture procedure and destructive negative controls remain
available in `docs/verification.md` for a future deployment.

### Ongoing cost and teardown

No demo resources remain and no ongoing demo charges are expected. For future
deployments, preserve all four local state files and destroy in this exact
order:

```bash
terraform -chdir=04-customer-connection destroy -input=false -var-file=demo.tfvars
terraform -chdir=03-isv-routing destroy -input=false -var-file=demo.tfvars
terraform -chdir=02-customer-core destroy -input=false -var-file=demo.tfvars
terraform -chdir=01-isv-core destroy -input=false -var-file=demo.tfvars
```

Afterward, verify that all six resource groups and all Bastion public IPs, disks, and Virtual WAN resources are gone before deleting local state.

## Prefix-derived naming and resource-group split

- **Decision:** Expose only `isv_prefix` and `customer_prefix`, defaulting to `fd-isv` and `fd-customer`. Derive all individual names with fixed role components and Azure type suffixes.
- **Decision:** Create network, workload, and Bastion resource groups for each side. Keep the complete NVA cluster in the ISV network group and keep every NIC with its VM.
- **Decision:** Place all NSGs in the network groups and associate them with subnets. Manage the Bastion subnet NSGs explicitly with the required Azure Bastion rules.
- **Decision:** Keep the ISV customer route table in the ISV network group. Keep customer-side routes on the Virtual Hub connections and managed route tables.
- **Decision:** Preserve `AzureBastionSubnet` as the required fixed Azure subnet name; all other managed resource names use type-specific suffixes.
