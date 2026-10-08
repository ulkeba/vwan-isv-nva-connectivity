# Verification runbook

This is a linear copy/paste runbook for proving route convergence, NVA
traversal, source-address preservation, and single-NVA failover.

## Prerequisites

Install `jq`, Terraform, Azure CLI, the Azure CLI `log-analytics` extension,
and OpenSSH. Sign in with `az login`, apply all four Terraform roots, and make
sure the demo SSH private key is readable.

On Ubuntu or WSL, install `jq` with:

```bash
sudo apt-get update
sudo apt-get install -y jq
az extension add --name log-analytics --allow-preview true
```

Run **every command below from the repository root in one ongoing interactive
Bash or zsh shell**. Do not change shells partway through: `environment.sh` is
sourced once and its variables are used by all later commands. Sourcing uses
the current shell, not the script's shebang.

## 1. Capture deployment outputs and load variables

The four JSON files are the initial deployment evidence. `environment.sh`
reads these exact paths with `jq`.

```bash
: "${DEPLOYMENT_NAME:?Set DEPLOYMENT_NAME before capturing outputs}"
: "${TF_WORKSPACE:?Set TF_WORKSPACE to DEPLOYMENT_NAME before capturing outputs}"
test "$TF_WORKSPACE" = "$DEPLOYMENT_NAME"
case "$DEPLOYMENT_NAME" in
  ""|[![:alnum:]]*|*[![:alnum:]_-]*)
    printf 'Invalid DEPLOYMENT_NAME: %s\n' "$DEPLOYMENT_NAME" >&2
    exit 1
    ;;
esac

test -f ./environment.sh
test -x ./scripts/show-effective-routes.sh
test -x ./scripts/show-nva-counters.sh
test -x ./scripts/test-connectivity.sh
command -v jq
az extension show --name log-analytics > /dev/null
export EVIDENCE_DIR="${EVIDENCE_DIR:-evidence_$DEPLOYMENT_NAME}"
mkdir -p "$EVIDENCE_DIR"

for root in 01-isv-core 02-customer-core 03-isv-routing 04-customer-connection; do
  test -s "$root/$DEPLOYMENT_NAME.tfvars"
done

terraform -chdir=01-isv-core output -json > "$EVIDENCE_DIR/01-isv-core.json"
terraform -chdir=02-customer-core output -json > "$EVIDENCE_DIR/02-customer-core.json"
terraform -chdir=03-isv-routing output -json > "$EVIDENCE_DIR/03-isv-routing.json"
terraform -chdir=04-customer-connection output -json > "$EVIDENCE_DIR/04-customer-connection.json"

source ./environment.sh
test -r "$SSH_KEY"

NVA_COUNTER_ARGS=()
for nva_vm_id in "${NVA_VM_IDS[@]}"; do
  NVA_COUNTER_ARGS+=(--nva-vm-id "$nva_vm_id")
done
unset nva_vm_id
```

The stage 01 and 02 evidence files are required. Stage 03 and 04 variables are
loaded when their evidence files become available, so the environment can be
sourced between Terraform stages. Source the file again after capturing
additional stage outputs.

To print file checks, skipped stages, validation phases, and export progress
while loading the environment, enable debug output:

```bash
ENVIRONMENT_DEBUG=1 source ./environment.sh
```

The administrator usernames are loaded from the Terraform output JSON. Record
them with the active Azure account:

```bash
az account show \
  --subscription "$AZURE_SUBSCRIPTION" \
  --output json > "$EVIDENCE_DIR/azure-account.json"
printf 'ISV administrator: %s\nCustomer administrator: %s\n' \
  "$ISV_ADMIN_USERNAME" "$CUSTOMER_ADMIN_USERNAME" \
  | tee "$EVIDENCE_DIR/admin-usernames.txt"
```

## 2. Confirm provisioning and routing state

```bash
az network vhub show \
  --ids "$VIRTUAL_HUB_ID" \
  --query '{provisioningState:provisioningState,routingState:routingState}' \
  --output json > "$EVIDENCE_DIR/virtual-hub-status.json"
az network vhub show \
  --ids "$VIRTUAL_HUB_ID" \
  --query '{provisioningState:provisioningState,routingState:routingState}' \
  --output table | tee "$EVIDENCE_DIR/virtual-hub-status.txt"

az network vhub connection show \
  --ids "$CUSTOMER_WORKLOAD_CONNECTION_ID" \
  --output json > "$EVIDENCE_DIR/customer-hub-connection-status.json"
az network vhub connection show \
  --ids "$CUSTOMER_WORKLOAD_CONNECTION_ID" \
  --query '{name:name,provisioningState:provisioningState}' \
  --output table | tee "$EVIDENCE_DIR/customer-hub-connection-status.txt"

az network vhub connection show \
  --ids "$ISV_HUB_CONNECTION_ID" \
  --output json > "$EVIDENCE_DIR/isv-hub-connection-status.json"
az network vhub connection show \
  --ids "$ISV_HUB_CONNECTION_ID" \
  --query '{name:name,provisioningState:provisioningState}' \
  --output table | tee "$EVIDENCE_DIR/isv-hub-connection-status.txt"
```

Continue only when the hub provisioning state is `Succeeded`, the hub routing
state is **`Provisioned`**, and both connections are `Succeeded`.

When `virtual_hub_deploy_firewall` is enabled, `environment.sh` loads the
firewall identifiers from the Terraform output JSON. Capture the provisioning
state:

```bash
az network firewall show \
  --ids "$CUSTOMER_FIREWALL_ID" \
  --output json > "$EVIDENCE_DIR/customer-firewall-status.json"
az resource show \
  --ids "$CUSTOMER_FIREWALL_ROUTING_INTENT_ID" \
  --output json > "$EVIDENCE_DIR/customer-firewall-routing-intent.json"
```

## 3. Inspect effective routes

Use the repository helper for tunnel-free route inspection:

```bash
./scripts/show-effective-routes.sh \
  --virtual-hub-id "$VIRTUAL_HUB_ID" \
  --customer-nic-id "$CUSTOMER_WORKLOAD_NIC_ID" \
  --isv-nic-id "$ISV_WORKLOAD_NIC_ID" \
  --nva-nic-id "$NVA_1_NIC_ID" \
  | tee "$EVIDENCE_DIR/effective-routes.txt"
```

Capture the underlying structured Azure CLI results separately:

```bash
az network vhub get-effective-routes \
  --ids "$VIRTUAL_HUB_ID" \
  --resource-type RouteTable \
  --resource-id "$DEFAULT_HUB_ROUTE_TABLE_ID" \
  --output json > "$EVIDENCE_DIR/virtual-hub-effective-routes.json"

az network nic show-effective-route-table \
  --ids "$CUSTOMER_WORKLOAD_NIC_ID" \
  --output json > "$EVIDENCE_DIR/customer-nic-effective-routes.json"
az network nic show-effective-route-table \
  --ids "$ISV_WORKLOAD_NIC_ID" \
  --output json > "$EVIDENCE_DIR/isv-nic-effective-routes.json"
az network nic show-effective-route-table \
  --ids "$NVA_1_NIC_ID" \
  --output json > "$EVIDENCE_DIR/nva-1-nic-effective-routes.json"
```

Confirm the customer learns the ISV prefix, the ISV workload sends the customer
prefix to `$NVA_LOAD_BALANCER_FRONTEND_IP`, and NVA 1 can route the customer
prefix through the hub. Routes support the traffic evidence; they do not
replace it.

When the configured ISV destination prefix covers the full VNet, the physical
workload subnet remains unchanged. No additional infrastructure deny rules are
configured. Keep the return-path UDR off the NVA and Bastion subnets, but do
not treat that as an ingress filter. The full connection route can affect hub
traffic addressed to their private IPs; ordinary Bastion public access and
local SSH use a different path.

With Internet Traffic Routing Intent only, confirm that the customer workload
NIC learns `0.0.0.0/0` through Azure Firewall while private routes retain the
NVA path. With Private Traffic Routing Intent also enabled, private hub routes
are expected to target Azure Firewall. Record the effective routes and use
packet captures and counters to establish the actual NVA and return paths;
do not treat Firewall private routes alone as a failed deployment.

## 4. Capture counters, then test both directions

Capture the baseline NVA counters. The helper owns the Bastion tunnel details.

```bash
./scripts/show-nva-counters.sh \
  --bastion-name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --admin-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  "${NVA_COUNTER_ARGS[@]}" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/nva-counters-before.txt"
```

Customer to ISV:

```bash
./scripts/test-connectivity.sh \
  --direction customer-to-isv \
  --source-bastion-name "$CUSTOMER_BASTION_NAME" \
  --source-resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --source-vm-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --source-username "$CUSTOMER_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --destination-ip "$ISV_WORKLOAD_PRIVATE_IP" \
  --expected-source-ip "$CUSTOMER_WORKLOAD_PRIVATE_IP" \
  --tcp-port 2000 \
  --destination-bastion-name "$ISV_BASTION_NAME" \
  --destination-resource-group "$ISV_RESOURCE_GROUP" \
  --destination-vm-id "$ISV_WORKLOAD_VM_ID" \
  --destination-username "$ISV_ADMIN_USERNAME" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/connectivity-customer-to-isv.txt"
```

ISV to customer:

```bash
./scripts/test-connectivity.sh \
  --direction isv-to-customer \
  --source-bastion-name "$ISV_BASTION_NAME" \
  --source-resource-group "$ISV_RESOURCE_GROUP" \
  --source-vm-id "$ISV_WORKLOAD_VM_ID" \
  --source-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --destination-ip "$CUSTOMER_WORKLOAD_PRIVATE_IP" \
  --expected-source-ip "$ISV_WORKLOAD_PRIVATE_IP" \
  --tcp-port 2000 \
  --destination-bastion-name "$CUSTOMER_BASTION_NAME" \
  --destination-resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --destination-vm-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --destination-username "$CUSTOMER_ADMIN_USERNAME" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/connectivity-isv-to-customer.txt"
```

Capture the counters again:

```bash
./scripts/show-nva-counters.sh \
  --bastion-name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --admin-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  "${NVA_COUNTER_ARGS[@]}" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/nva-counters-after.txt"
```

Successful raw TCP checks on port 2000, destination-observed source addresses,
and increasing NVA counters are the authoritative result. No HTTP protocol is
used. ICMP is only supporting evidence.

## 5. Prove NVA 1 failover (disruptive)

This procedure requires at least two NVAs. Skip section 5 when `NVA_COUNT` is
`1`; the interactive capture in section 6 still works with one NVA.

```bash
test "$NVA_COUNT" -ge 2
```

> **WARNING:** These commands stop NVA 1. Never stop every NVA. There is no
> automatic restoration if the shell, terminal, or command sequence is
> interrupted. Copy the restore command below somewhere accessible before
> starting, and run it immediately after the failover test.

**NVA 1 restore command:**

```bash
az vm start \
  --ids "$NVA_1_VM_ID"
```

Stop NVA 1 and record its state:

```bash
az vm stop \
  --ids "$NVA_1_VM_ID"
az vm wait \
  --ids "$NVA_1_VM_ID" \
  --updated \
  --custom "instanceView.statuses[?code=='PowerState/stopped']"
az vm get-instance-view \
  --ids "$NVA_1_VM_ID" \
  --output json > "$EVIDENCE_DIR/nva-1-stopped-instance-view.json"
sleep 30
```

Test customer-to-ISV traffic while NVA 1 is stopped:

```bash
./scripts/test-connectivity.sh \
  --direction customer-to-isv \
  --source-bastion-name "$CUSTOMER_BASTION_NAME" \
  --source-resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --source-vm-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --source-username "$CUSTOMER_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --destination-ip "$ISV_WORKLOAD_PRIVATE_IP" \
  --expected-source-ip "$CUSTOMER_WORKLOAD_PRIVATE_IP" \
  --tcp-port 2000 \
  --destination-bastion-name "$ISV_BASTION_NAME" \
  --destination-resource-group "$ISV_RESOURCE_GROUP" \
  --destination-vm-id "$ISV_WORKLOAD_VM_ID" \
  --destination-username "$ISV_ADMIN_USERNAME" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/failover-customer-to-isv.txt"
```

Test ISV-to-customer traffic while NVA 1 is stopped:

```bash
./scripts/test-connectivity.sh \
  --direction isv-to-customer \
  --source-bastion-name "$ISV_BASTION_NAME" \
  --source-resource-group "$ISV_RESOURCE_GROUP" \
  --source-vm-id "$ISV_WORKLOAD_VM_ID" \
  --source-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --destination-ip "$CUSTOMER_WORKLOAD_PRIVATE_IP" \
  --expected-source-ip "$ISV_WORKLOAD_PRIVATE_IP" \
  --tcp-port 2000 \
  --destination-bastion-name "$CUSTOMER_BASTION_NAME" \
  --destination-resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --destination-vm-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --destination-username "$CUSTOMER_ADMIN_USERNAME" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/failover-isv-to-customer.txt"
```

**Restore NVA 1 now, even if the traffic test failed:**

```bash
az vm start \
  --ids "$NVA_1_VM_ID"
az vm wait \
  --ids "$NVA_1_VM_ID" \
  --updated \
  --custom "instanceView.statuses[?code=='PowerState/running']"
az vm get-instance-view \
  --ids "$NVA_1_VM_ID" \
  --output json > "$EVIDENCE_DIR/nva-1-restored-instance-view.json"
```

Capture counters and confirm one or more remaining NVAs handled the failover
traffic:

```bash
./scripts/show-nva-counters.sh \
  --bastion-name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --admin-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  "${NVA_COUNTER_ARGS[@]}" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/nva-counters-after-failover.txt"
```

## 6. Observe forwarded traffic interactively

With multiple NVAs, this test stops every NVA except NVA 1 so the load
balancer must select NVA 1; this is disruptive. With one NVA, skip the VM
start/stop/restore commands and leave it running.

Use three interactive SSH sessions and, when Firewall is enabled, a fourth
local terminal:

1. NVA 1, running `tcpdump`.
2. The ISV workload VM, listening on raw TCP port 2000.
3. The customer workload VM, sending a short message to that listener.
4. The local repository shell, querying structured Azure Firewall logs.

> **WARNING:** Never stop every NVA. There is no automatic restoration if a
> terminal closes or a command is interrupted. Copy the restore command below
> somewhere accessible before starting.

**Restore all stopped NVAs:**

```bash
for nva_vm_id in "${NVA_VM_IDS[@]:1}"; do
  az vm start --ids "$nva_vm_id"
done
unset nva_vm_id
```

Ensure NVA 1 is running before stopping the other NVAs:

```bash
az vm start \
  --ids "$NVA_1_VM_ID"
az vm wait \
  --ids "$NVA_1_VM_ID" \
  --updated \
  --custom "instanceView.statuses[?code=='PowerState/running']"
```

Stop every other NVA and wait for Azure to report each one stopped:

```bash
for nva_vm_id in "${NVA_VM_IDS[@]:1}"; do
  nva_name="${nva_vm_id##*/}"
  az vm stop --ids "$nva_vm_id"
  az vm wait \
    --ids "$nva_vm_id" \
    --updated \
    --custom "instanceView.statuses[?code=='PowerState/stopped']"
  az vm get-instance-view \
    --ids "$nva_vm_id" \
    --output json > "$EVIDENCE_DIR/interactive-$nva_name-stopped.json"
done
unset nva_vm_id nva_name
sleep 30
```

### Terminal 1: capture forwarded packets on NVA 1

Open an interactive SSH session:

```bash
az network bastion ssh \
  --name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --target-resource-id "$NVA_1_VM_ID" \
  --auth-type ssh-key \
  --username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --subscription "$AZURE_SUBSCRIPTION"
```

In the NVA 1 SSH session, start the `tcpdump` installed by cloud-init. The IP
addresses below are the checked-in demo workload addresses:

```bash
sudo tcpdump -lnni any \
  'host 10.10.1.10 and host 192.168.1.4 and tcp port 2000' \
  | grep --line-buffered ' eth0 '
```

Capturing on `any` retains Linux's `In` and `Out` direction metadata. Filtering
the displayed output to `eth0` removes duplicate observations from Azure
Accelerated Networking's virtual-function interface. Leave `tcpdump` running.
Press `Ctrl+C` after the message has been sent.

### Terminal 2: listen on the ISV workload VM

Open another interactive SSH session:

```bash
az network bastion ssh \
  --name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --target-resource-id "$ISV_WORKLOAD_VM_ID" \
  --auth-type ssh-key \
  --username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --subscription "$AZURE_SUBSCRIPTION"
```

In the ISV workload SSH session, use the netcat installed by cloud-init to
listen on raw TCP port 2000:

```bash
nc -lk 2000
```

Leave the listener running.

### Terminal 3: send from the customer workload VM

Open a third interactive SSH session:

```bash
az network bastion ssh \
  --name "$CUSTOMER_BASTION_NAME" \
  --resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --target-resource-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --auth-type ssh-key \
  --username "$CUSTOMER_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --subscription "$AZURE_SUBSCRIPTION"
```

In the customer workload SSH session, use the netcat installed by cloud-init
to send a short message to the ISV workload:

```bash
echo 'hello-through-nva' | nc -w 3 192.168.1.4 2000
```

The ISV workload listener in terminal 2 should print:

```text
hello-through-nva
```

NVA 1 in terminal 1 should show packet metadata for the TCP handshake, data
packet, and acknowledgments. Packet payload is intentionally not printed. The
ephemeral source port, sequence numbers, and timestamps will differ, but the
relevant lines should resemble:

```text
eth0 In  IP 10.10.1.10.54321 > 192.168.1.4.2000: Flags [S]
eth0 Out IP 10.10.1.10.54321 > 192.168.1.4.2000: Flags [S]
eth0 In  IP 192.168.1.4.2000 > 10.10.1.10.54321: Flags [S.]
eth0 In  IP 10.10.1.10.54321 > 192.168.1.4.2000: Flags [P.], length 18
```

The `In` and `Out` observations on `eth0` prove that NVA 1 received and
forwarded the connection. The unchanged source and destination addresses prove
that it forwarded the flow without SNAT.

### Terminal 4: inspect structured Azure Firewall logs

Return to the local repository shell. Export one query that combines the
network-rule decision with Flow Trace TCP lifecycle events for only the private
TCP/2000 flow:

```bash
export FIREWALL_TCP_2000_QUERY="
union isfuzzy=true
(
    AZFWNetworkRule
    | where TimeGenerated > ago(30m)
    | where _ResourceId =~ '$CUSTOMER_FIREWALL_ID'
    | where SourceIp == '$CUSTOMER_WORKLOAD_PRIVATE_IP'
    | where DestinationIp == '$ISV_WORKLOAD_PRIVATE_IP'
    | where DestinationPort == 2000
    | project TimeGenerated, RecordType = 'NetworkRule', SourceIp, SourcePort,
              DestinationIp, DestinationPort, Protocol, Action,
              Detail = strcat(RuleCollection, '/', Rule)
),
(
    AZFWFlowTrace
    | where TimeGenerated > ago(30m)
    | where _ResourceId =~ '$CUSTOMER_FIREWALL_ID'
    | where SourceIp == '$CUSTOMER_WORKLOAD_PRIVATE_IP'
    | where DestinationIp == '$ISV_WORKLOAD_PRIVATE_IP'
    | where DestinationPort == 2000
    | project TimeGenerated, RecordType = 'FlowTrace', SourceIp, SourcePort,
              DestinationIp, DestinationPort, Protocol, Action,
              Detail = strcat(Flag, ' ', ActionReason)
)
| order by TimeGenerated asc
"
```

Continuously render the combined results as a table. Azure Monitor ingestion
can take up to 30 minutes after a diagnostic category is first enabled;
`watch` refreshes the query every ten seconds while the records arrive:

```bash
watch --interval 10 --no-title \
  'az monitor log-analytics query \
    --workspace "$CUSTOMER_FIREWALL_LOG_ANALYTICS_WORKSPACE_ID" \
    --analytics-query "$FIREWALL_TCP_2000_QUERY" \
    --output table'
```

Leave `watch` running and resend the netcat message from terminal 3. On a new
diagnostic setting, repeat the send after the initial 30-minute warm-up if Flow
Trace is still empty.

Interpret the continuously refreshed results together with the routing intent
captured earlier:

- With only the `InternetTraffic` policy enabled, a successful TCP/2000
  connection should appear on the NVA capture and normally produce no Azure
  Firewall record.
- With the `PrivateTraffic` policy enabled, the TCP/2000 attempt is sent to
  Azure Firewall and should produce a network-rule record. Root 04 no longer
  configures an explicit propagated-route-table block, so capture the actual
  NVA traversal and return-path behavior rather than assuming the result of the
  earlier Routing Intent experiment.

A network-rule row proves the Firewall policy decision, while Flow Trace adds
the TCP lifecycle flags. An empty result alone does not prove Firewall bypass
because ingestion can be delayed or misconfigured. Press `Ctrl+C` to stop
`watch`, `tcpdump`, and netcat, then close the three SSH sessions.

**Restore every stopped NVA now:**

```bash
for nva_vm_id in "${NVA_VM_IDS[@]:1}"; do
  nva_name="${nva_vm_id##*/}"
  az vm start --ids "$nva_vm_id"
  az vm wait \
    --ids "$nva_vm_id" \
    --updated \
    --custom "instanceView.statuses[?code=='PowerState/running']"
  az vm get-instance-view \
    --ids "$nva_vm_id" \
    --output json > "$EVIDENCE_DIR/interactive-$nva_name-restored.json"
done
unset nva_vm_id nva_name
```

Wait for every restored load-balancer backend probe to recover before
continuing.

## 7. Negative controls (optional and destructive)

> **STRONG WARNING:** Each control intentionally destroys managed routing
> resources and interrupts connectivity. Run only in an approved maintenance
> window. Run only one control at a time. There is no automatic restoration
> after interruption. The commands are interactive and intentionally omit
> `-auto-approve`; read every Terraform prompt before approving. These examples
> use the active `${DEPLOYMENT_NAME}.tfvars` and matching workspace selected in
> section 1.

### Remove and restore the ISV return-path route

Destroy the route layer:

```bash
terraform -chdir=03-isv-routing destroy \
  -input=true \
  -no-color \
  -var-file="$DEPLOYMENT_NAME.tfvars" \
  | tee "$EVIDENCE_DIR/negative-udr-destroy.txt"
```

Run customer-to-ISV traffic with the destination observer. Without the UDR,
the result may be failed connectivity or a return path that bypasses the NVA.
Compare the NVA counters with the earlier baseline to identify the result:

```bash
./scripts/test-connectivity.sh \
  --direction customer-to-isv \
  --source-bastion-name "$CUSTOMER_BASTION_NAME" \
  --source-resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --source-vm-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --source-username "$CUSTOMER_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --destination-ip "$ISV_WORKLOAD_PRIVATE_IP" \
  --expected-source-ip "$CUSTOMER_WORKLOAD_PRIVATE_IP" \
  --tcp-port 2000 \
  --destination-bastion-name "$ISV_BASTION_NAME" \
  --destination-resource-group "$ISV_RESOURCE_GROUP" \
  --destination-vm-id "$ISV_WORKLOAD_VM_ID" \
  --destination-username "$ISV_ADMIN_USERNAME" \
  --subscription "$AZURE_SUBSCRIPTION" \
  2>&1 | tee "$EVIDENCE_DIR/negative-udr-connectivity.txt" \
  || printf 'Connectivity failure observed with the ISV route removed.\n'
```

Restore the route layer immediately:

```bash
terraform -chdir=03-isv-routing apply \
  -input=true \
  -no-color \
  -var-file="$DEPLOYMENT_NAME.tfvars" \
  | tee "$EVIDENCE_DIR/negative-udr-restore.txt"
```

### Remove and restore the customer-managed ISV connection

Destroy the connection layer:

```bash
terraform -chdir=04-customer-connection destroy \
  -input=true \
  -no-color \
  -var-file="$DEPLOYMENT_NAME.tfvars" \
  | tee "$EVIDENCE_DIR/negative-connection-destroy.txt"
```

Confirm customer-to-ISV traffic no longer succeeds:

```bash
./scripts/test-connectivity.sh \
  --direction customer-to-isv \
  --source-bastion-name "$CUSTOMER_BASTION_NAME" \
  --source-resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --source-vm-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --source-username "$CUSTOMER_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --destination-ip "$ISV_WORKLOAD_PRIVATE_IP" \
  --expected-source-ip "$CUSTOMER_WORKLOAD_PRIVATE_IP" \
  --tcp-port 2000 \
  --destination-bastion-name "$ISV_BASTION_NAME" \
  --destination-resource-group "$ISV_RESOURCE_GROUP" \
  --destination-vm-id "$ISV_WORKLOAD_VM_ID" \
  --destination-username "$ISV_ADMIN_USERNAME" \
  --subscription "$AZURE_SUBSCRIPTION" \
  2>&1 | tee "$EVIDENCE_DIR/negative-connection-connectivity.txt" \
  || printf 'Expected failure observed with the ISV connection removed.\n'
```

Restore the connection layer immediately:

```bash
terraform -chdir=04-customer-connection apply \
  -input=true \
  -no-color \
  -var-file="$DEPLOYMENT_NAME.tfvars" \
  | tee "$EVIDENCE_DIR/negative-connection-restore.txt"
```

After either negative control, repeat sections 2 through 4 only after the hub
routing state returns to `Provisioned`.

## 8. Cleanup

Keep the named evidence files until the results have been reviewed and
archived. To destroy the deployed infrastructure, use reverse dependency order
and review each interactive confirmation:

```bash
terraform -chdir=04-customer-connection destroy \
  -input=true -var-file="$DEPLOYMENT_NAME.tfvars"
terraform -chdir=03-isv-routing destroy \
  -input=true -var-file="$DEPLOYMENT_NAME.tfvars"
terraform -chdir=02-customer-core destroy \
  -input=true -var-file="$DEPLOYMENT_NAME.tfvars"
terraform -chdir=01-isv-core destroy \
  -input=true -var-file="$DEPLOYMENT_NAME.tfvars"
```

Confirm that both resource groups and all billable Public IP, Bastion, disk,
load-balancer, and Virtual WAN resources are gone. Remove local evidence only
after it has been archived:

```bash
printf 'Evidence directory retained at: %s\n' "$EVIDENCE_DIR"
rm -ri -- "$EVIDENCE_DIR"
```
