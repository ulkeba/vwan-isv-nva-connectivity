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
| Azure deployment | Complete | All four roots applied in order; all control-plane states succeeded |
| Smoke checks and handoff | Complete | Both directions and no-SNAT verified; NVA counters increased; four post-deployment plans show no drift |

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
- **Decision:** Generate an Ed25519 key pair at `~/.ssh/ecs-vwan-fwaas-demo`; Terraform receives only the public key.
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
- **Decision:** Each verification run captures one `.json` Terraform output file for each of the four deployment layers. The committed root `environment.sh` loads resource identifiers, names, addresses, and prefixes from those files with `jq`. NVA values use explicit `ecs-vwan-isv-nva-1` and `ecs-vwan-isv-nva-2` map keys.
- **Rationale:** Operators can inspect four explicit capture commands, source the environment once in an ongoing shell, and paste the remaining linear commands without replacing placeholders or relying on object ordering.
- **Consequence:** `jq` is a verification prerequisite. Verification artifacts are stored under the ignored `evidence/` directory and must be regenerated and re-sourced after infrastructure changes.

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
- Dedicated Ed25519 key generated at `~/.ssh/ecs-vwan-fwaas-demo`; its fingerprint is `SHA256:szFZ1/mGFD6qsIA8MkPLwssJdyTpcHKQMsmgkVvO9YI`.
- Active Azure subscription and identity were checked before implementation. Required Compute, Network, and Storage providers are registered.
- Sweden Central preflight found `Standard_B2s` available in zones 1, 2, and 3, with 100 regional vCPUs and 100 BS-family vCPUs permitted at the time of the check.
- `bash -n` passes for all three operations scripts; each script is executable and its `--help` path succeeds.
- `diagrams/architecture.drawio` and `diagrams/architecture.svg` parse successfully as XML.
- `04-customer-connection` and `03-isv-routing` initialize and validate successfully with AzureRM `5.6.0`.
- `terraform fmt -recursive` and `terraform validate` pass for all four roots.
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
- The verification guide was simplified into 24 linear copy-and-paste Bash blocks. It writes four per-layer Terraform JSON snapshots, sources 27 JSON-derived values from the committed `environment.sh` using `jq`, and captures Azure status, routes, counters, and connectivity evidence.
- The simplified workflow was validated against the deployed environment: all four JSON captures are valid, all derived values are non-empty, NVA name-keyed lookups resolve correctly, Azure hub and connection state checks pass, every Bash block passes `bash -n`, and no angle-bracket placeholders or inline control structures remain.

## Deployment handoff

### Deployed resources

- **Subscription:** `eaf4193c-36fa-42b9-b284-5ef3f7e8646c`
- **Region:** Sweden Central
- **ISV resource group:** `rg-ecs-vwan-isv-core-demo`
- **ISV VNet:** `vnet-ecs-vwan-isv-demo`
- **ISV workload VM:** `vm-ecs-vwan-isv-workload-demo` (`10.100.1.4`)
- **NVA load balancer:** `ecs-vwan-isv-nva-lb` (`10.100.0.10`)
- **NVA VMs:** `ecs-vwan-isv-nva-1` (`10.100.0.5`, zone 1) and `ecs-vwan-isv-nva-2` (`10.100.0.4`, zone 2)
- **ISV route table:** `rt-ecs-vwan-isv-to-customer-demo`
- **Customer resource group:** `rg-vwan-customer-demo`
- **Virtual WAN / hub:** `vwan-customer-demo` / `vhub-customer-demo`
- **Customer VNet:** `vnet-customer-demo`
- **Customer workload VM:** `vm-customer-workload-demo` (`10.10.1.10`)
- **Hub connections:** `conn-customer-workload-demo` and `conn-isv-demo`

### Remaining interactive verification

The user requested that resources remain deployed for verification. The following intentional disruptions were not automated:

- Stop either NVA, wait for probe convergence, and repeat both directional tests.
- Destroy and restore `03-isv-routing` to exercise the return-path negative control.
- Destroy and restore `04-customer-connection` to exercise the connection negative control.

Follow `docs/verification.md` for commands and evidence requirements.

### Ongoing cost and teardown

Two Bastion Standard hosts and the Standard Virtual WAN hub continue accruing charges. Preserve all four local state files and destroy in this exact order:

```bash
terraform -chdir=04-customer-connection destroy -input=false -var-file=demo.tfvars
terraform -chdir=03-isv-routing destroy -input=false -var-file=demo.tfvars
terraform -chdir=02-customer-core destroy -input=false -var-file=demo.tfvars
terraform -chdir=01-isv-core destroy -input=false -var-file=demo.tfvars
```

Afterward, verify that both resource groups and all Bastion public IPs, disks, and Virtual WAN resources are gone before deleting local state.
