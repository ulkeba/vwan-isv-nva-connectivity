# Interactive flow inspection

Use this guide after the four deployments in [README.md](../README.md#deploy):

1. Load the deployment environment.
2. Inspect a customer-initiated TCP flow on the NVA and workload VMs.
3. Follow Azure Firewall logs when Firewall is enabled.

The walkthrough keeps all VMs running and does not change routing. If something fails, use [Troubleshooting](#troubleshooting).

## 1. Load the environment

Run locally from the repository root in the **Zsh session** used for deployment. This step captures the output files that each terminal will load in section 2.

### Prechecks

Run these checks first. They are independent checks, not an automatically aborting script: **resolve every reported error before running the collection sequence below**.

```zsh
set -o pipefail
export EVIDENCE_DIR="${EVIDENCE_DIR:-evidence_$DEPLOYMENT_NAME}"
export SSH_KEY="${SSH_KEY:-$HOME/.ssh/fd-fwaas-demo}"

for tool in terraform az jq ssh; do
  if ! command -v "$tool" >/dev/null; then
    printf 'ERROR: %s is missing. Install it and add it to PATH before collecting outputs.\n' "$tool" >&2
    false
  fi
done
if [[ -z "${DEPLOYMENT_NAME:-}" || ! "$DEPLOYMENT_NAME" =~ ^[[:alnum:]][[:alnum:]_-]*$ ]]; then
  printf 'ERROR: Missing or invalid DEPLOYMENT_NAME. Set it to the local deployment name used for apply.\n' >&2
  false
fi
if [[ -z "${TF_WORKSPACE:-}" || "$TF_WORKSPACE" != "${DEPLOYMENT_NAME:-}" ]]; then
  printf 'ERROR: TF_WORKSPACE="%s" must match DEPLOYMENT_NAME="%s". Run: export TF_WORKSPACE="$DEPLOYMENT_NAME"\n' "${TF_WORKSPACE:-<unset>}" "${DEPLOYMENT_NAME:-<unset>}" >&2
  false
fi
if [[ ! -f ./environment.sh ]]; then
  printf 'ERROR: environment.sh is missing in %s. Change to the repository root before continuing.\n' "$PWD" >&2
  false
fi
for root in 01-isv-core 02-customer-core 03-isv-routing 04-customer-connection; do
  if [[ ! -s "$root/$DEPLOYMENT_NAME.tfvars" ]]; then
    printf 'ERROR: Missing or empty %s/%s.tfvars. Restore the local configuration used for this deployment.\n' "$root" "$DEPLOYMENT_NAME" >&2
    false
  fi
done
if [[ ! -r "$SSH_KEY" ]]; then
  printf 'ERROR: SSH key "%s" is not readable. Set SSH_KEY to the private key matching the deployed public key.\n' "$SSH_KEY" >&2
  false
fi
```

### Collect outputs and load the environment

Run this sequence only after all prechecks pass. Each progress line identifies the root being captured; `&&` prevents further collection and environment loading if an operation fails.

```zsh
if mkdir -p "$EVIDENCE_DIR" &&
  printf 'Collecting 01-isv-core outputs\n' &&
  terraform -chdir=01-isv-core output -json > "$EVIDENCE_DIR/01-isv-core.json" &&
  printf 'Collecting 02-customer-core outputs\n' &&
  terraform -chdir=02-customer-core output -json > "$EVIDENCE_DIR/02-customer-core.json" &&
  printf 'Collecting 03-isv-routing outputs\n' &&
  terraform -chdir=03-isv-routing output -json > "$EVIDENCE_DIR/03-isv-routing.json" &&
  printf 'Collecting 04-customer-connection outputs\n' &&
  terraform -chdir=04-customer-connection output -json > "$EVIDENCE_DIR/04-customer-connection.json"; then
  if source ./environment.sh; then
    printf 'Customer workload IP: %s\nISV workload IP: %s\n' \
      "$CUSTOMER_WORKLOAD_PRIVATE_IP" "$ISV_WORKLOAD_PRIVATE_IP"
  else
    printf 'ERROR: Environment loading failed. Resolve the loader messages above and check the captured JSON for this deployment.\n' >&2
    false
  fi
else
  printf 'ERROR: Output collection failed. Check the last reported root, its workspace/applied state, and evidence-directory permissions before retrying.\n' >&2
  false
fi
```

`environment.sh` loads resource IDs, usernames, and NVA variables from the captured JSON. It uses the `SSH_KEY` path checked above. Stop on errors, correct the reported problem, and rerun the failed sequence; none of these commands closes your terminal.

## 2. Inspect the workload flow

Open **four separate local Zsh terminals**, all starting in the repository root:

| Terminal | Role |
|---|---|
| NVA terminal | Bastion SSH to the NVA, running tcpdump |
| ISV terminal | Bastion SSH to the ISV workload, running the listener |
| Customer terminal | Bastion SSH to the customer workload, sending messages |
| Firewall terminal | Stay local and run the live log monitor in section 3 |

**Run the following environment setup in every terminal, including the Firewall terminal, before its role-specific commands.** Use the same deployment name, evidence directory, and private key as section 1. Each terminal has its own shell environment; initializing one does not initialize the others. With multiple NVAs, open an additional initialized terminal and capture on each healthy backend.

```zsh
set -o pipefail
export DEPLOYMENT_NAME=local-demo
export TF_WORKSPACE="$DEPLOYMENT_NAME"
export EVIDENCE_DIR="evidence_$DEPLOYMENT_NAME"
# If using a different private key, export SSH_KEY here before loading.
if ! source ./environment.sh; then
  printf 'ERROR: Environment loading failed in this terminal. Match section 1 settings and resolve the loader messages before opening SSH or monitoring logs.\n' >&2
  false
fi
```

Replace the example exports if your deployment differs. Verify the private key checked in section 1 is readable in each terminal, and stop if environment loading fails. Run this setup **locally before opening SSH**; remote commands below do not need the local environment variables. The remote commands use the VM's existing shell and do not require installing Zsh on the VMs.

**Default IPs:** the tcpdump and netcat examples use customer `10.10.1.10` and ISV `192.168.1.4`, matching the demo tfvars. If you changed ranges or VM private IPs, replace these literals with the addresses printed in section 1.

### NVA terminal: capture

Run locally. For additional NVAs, use `NVA_2_VM_ID` or `NVA_3_VM_ID`:

```zsh
az network bastion ssh \
  --name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --target-resource-id "$NVA_1_VM_ID" \
  --auth-type ssh-key \
  --username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --subscription "$AZURE_SUBSCRIPTION"
```

Run **on the NVA** and leave the capture running:

```zsh
sudo tcpdump -lnni any \
  'host 10.10.1.10 and host 192.168.1.4 and tcp port 2000' \
  | grep --line-buffered ' eth0 '
```

`any` retains Linux ingress/egress metadata. The line-buffered grep displays only `eth0`, removing duplicate observations from interfaces such as `enP39...` while keeping output live. Match the same IP/port tuple entering and leaving the NVA to establish forwarding.

### ISV terminal: listen

Run locally:

```zsh
az network bastion ssh \
  --name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --target-resource-id "$ISV_WORKLOAD_VM_ID" \
  --auth-type ssh-key \
  --username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --subscription "$AZURE_SUBSCRIPTION"
```

Run **on the ISV workload** and leave the listener running:

```zsh
nc -lnvk 2000
```

The verbose listener prints the connecting peer's IP and received messages.

### Customer terminal: send

Run locally:

```zsh
az network bastion ssh \
  --name "$CUSTOMER_BASTION_NAME" \
  --resource-group "$CUSTOMER_RESOURCE_GROUP" \
  --target-resource-id "$CUSTOMER_WORKLOAD_VM_ID" \
  --auth-type ssh-key \
  --username "$CUSTOMER_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --subscription "$AZURE_SUBSCRIPTION"
```

Run **on the customer workload**, customizing the destination if needed:

```zsh
printf 'hello-through-nva\n' | nc -w 3 192.168.1.4 2000
```

The ISV listener should print `hello-through-nva` and report the original customer IP (`10.10.1.10` by default). A message or unchanged peer IP alone does not prove NVA traversal; inspect the request and reply packets.

### Expected NVA capture

**Both requests and replies must enter and leave the NVA path.** The output should resemble the following sample. Timestamps, ephemeral ports, sequence numbers, and TCP options vary; customized addresses will differ:

```text
08:46:58.440874 eth0  In  IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [S], seq 2504157354, win 64240, options [mss 1376,sackOK,TS val 1470980990 ecr 0,nop,wscale 10], length 0
08:46:58.440901 eth0  Out IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [S], seq 2504157354, win 64240, options [mss 1376,sackOK,TS val 1470980990 ecr 0,nop,wscale 10], length 0
08:46:58.442983 eth0  In  IP 192.168.1.4.2000 > 10.10.1.10.55582: Flags [S.], seq 2893647747, ack 2504157355, win 65160, options [mss 1418,sackOK,TS val 4208439375 ecr 1470980990,nop,wscale 10], length 0
08:46:58.442987 eth0  Out IP 192.168.1.4.2000 > 10.10.1.10.55582: Flags [S.], seq 2893647747, ack 2504157355, win 65160, options [mss 1418,sackOK,TS val 4208439375 ecr 1470980990,nop,wscale 10], length 0
08:46:58.448749 eth0  In  IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [.], ack 1, win 63, options [nop,nop,TS val 1470981001 ecr 4208439375], length 0
08:46:58.448749 eth0  In  IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [P.], seq 1:19, ack 1, win 63, options [nop,nop,TS val 1470981001 ecr 4208439375], length 18
08:46:58.448758 eth0  Out IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [.], ack 1, win 63, options [nop,nop,TS val 1470981001 ecr 4208439375], length 0
08:46:58.448762 eth0  Out IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [P.], seq 1:19, ack 1, win 63, options [nop,nop,TS val 1470981001 ecr 4208439375], length 18
08:46:58.449112 eth0  In  IP 192.168.1.4.2000 > 10.10.1.10.55582: Flags [.], ack 19, win 64, options [nop,nop,TS val 4208439382 ecr 1470981001], length 0
08:46:58.449116 eth0  Out IP 192.168.1.4.2000 > 10.10.1.10.55582: Flags [.], ack 19, win 64, options [nop,nop,TS val 4208439382 ecr 1470981001], length 0
08:47:01.452029 eth0  In  IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [F.], seq 19, ack 1, win 63, options [nop,nop,TS val 1470984004 ecr 4208439382], length 0
08:47:01.452051 eth0  Out IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [F.], seq 19, ack 1, win 63, options [nop,nop,TS val 1470984004 ecr 4208439382], length 0
08:47:01.452607 eth0  In  IP 192.168.1.4.2000 > 10.10.1.10.55582: Flags [F.], seq 1, ack 20, win 64, options [nop,nop,TS val 4208442385 ecr 1470984004], length 0
08:47:01.452611 eth0  Out IP 192.168.1.4.2000 > 10.10.1.10.55582: Flags [F.], seq 1, ack 20, win 64, options [nop,nop,TS val 4208442385 ecr 1470984004], length 0
08:47:01.453603 eth0  In  IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [.], ack 2, win 63, options [nop,nop,TS val 1470984006 ecr 4208442385], length 0
08:47:01.453606 eth0  Out IP 10.10.1.10.55582 > 192.168.1.4.2000: Flags [.], ack 2, win 63, options [nop,nop,TS val 1470984006 ecr 4208442385], length 0
```

- The customer SYN (`[S]`) has paired `In` and `Out` lines with the same original source IP.
- The ISV SYN-ACK (`[S.]`) also has paired `In` and `Out` lines, proving the reply crosses the NVA.
- Data (`[P.]`), acknowledgments (`[.]`), and connection close (`[F.]`) show the same pattern.

**If only one traffic direction passes through the NVA path, routing is asymmetric.** With multiple NVAs, inspect all captures before concluding that requests or replies bypass the cluster; a direction may traverse a different healthy NVA. Missing packets in one capture can also result from capture loss or filtering. This walkthrough inspects both directions of one customer-initiated connection, not a separate ISV-initiated connection.

Keep the ISV listener and NVA capture running while following Firewall logs. Resend from the customer terminal as needed.

## 3. Inspect Firewall logs

Use the **separate local Firewall terminal initialized in section 2**. Do not run these commands inside a Bastion SSH session. The query uses actual resource IDs and workload IPs from that terminal's environment.

Skip this section when Firewall is disabled. Install `watch` if needed; on macOS with Homebrew, use `brew install watch`. The Azure CLI `log-analytics` extension is also required. Flow Trace additionally needs `AFWEnableTcpConnectionLogging`; see [logging troubleshooting](#firewall-logs-are-missing).

```zsh
if [[ -z "${CUSTOMER_FIREWALL_ID:-}" || -z "${CUSTOMER_FIREWALL_LOG_ANALYTICS_WORKSPACE_ID:-}" || -z "${CUSTOMER_WORKLOAD_PRIVATE_IP:-}" || -z "${ISV_WORKLOAD_PRIVATE_IP:-}" ]]; then
  printf 'ERROR: Firewall or workload data is not loaded. Skip if Firewall is disabled; otherwise rerun the section 2 setup in this terminal.\n' >&2
  false
fi
if ! command -v watch >/dev/null; then
  printf 'ERROR: watch is missing. On macOS run brew install watch; on Linux install your distribution'\''s watch package.\n' >&2
  false
fi
if ! az extension show --name log-analytics >/dev/null; then
  printf 'ERROR: Install the CLI extension with: az extension add --name log-analytics --allow-preview true\n' >&2
  false
fi
```

Resolve any errors above before constructing the query and starting the monitor:

```zsh
export FIREWALL_TCP_QUERY="
union isfuzzy=true
(
    AZFWNetworkRule
    | where TimeGenerated > ago(30m) and _ResourceId =~ '$CUSTOMER_FIREWALL_ID'
    | where SourceIp == '$CUSTOMER_WORKLOAD_PRIVATE_IP'
        and DestinationIp == '$ISV_WORKLOAD_PRIVATE_IP' and DestinationPort == 2000
    | project TimeGenerated, RecordType = 'NetworkRule', SourceIp, SourcePort,
        DestinationIp, DestinationPort, Protocol, Action,
        Detail = strcat(RuleCollection, '/', Rule)
),
(
    AZFWFlowTrace
    | where TimeGenerated > ago(30m) and _ResourceId =~ '$CUSTOMER_FIREWALL_ID'
    | where SourceIp == '$CUSTOMER_WORKLOAD_PRIVATE_IP'
        and DestinationIp == '$ISV_WORKLOAD_PRIVATE_IP' and DestinationPort == 2000
    | project TimeGenerated, RecordType = 'FlowTrace', SourceIp, SourcePort,
        DestinationIp, DestinationPort, Protocol, Action,
        Detail = strcat(Flag, ' ', ActionReason)
)
| order by TimeGenerated asc
"
watch -n 10 -x az monitor log-analytics query \
  --workspace "$CUSTOMER_FIREWALL_LOG_ANALYTICS_WORKSPACE_ID" \
  --analytics-query "$FIREWALL_TCP_QUERY" \
  -o table
```

`watch` refreshes the table every ten seconds; `-x` passes the multiline query directly to Azure CLI without another shell interpreting it. Leave this monitor running and resend the message from the customer terminal. Keep the ISV listener and NVA capture running in their own terminals. Press `Ctrl+C` in each terminal to stop its monitor, capture, or listener when finished.

New diagnostic settings can take up to 30 minutes to start delivering logs. A network-rule record proves a Firewall policy decision; Flow Trace adds TCP lifecycle details. Neither proves NVA traversal. Empty results do not prove Firewall bypass, and missing-table/query errors are not successful empty results. Correlate timestamps and flow tuples with the NVA capture.

## Troubleshooting

Run these diagnostics in an initialized **local terminal**, except where a remote NVA command is explicitly identified. [Routing Intent constraints](../design.md#optional-firewall-and-routing-intent) can affect the observed path; `Contains` or a propagated route alone does not guarantee NVA traversal.

### Deployment or connections are not ready

```zsh
az network vhub show \
  --ids "$VIRTUAL_HUB_ID" \
  --query '{provisioning:provisioningState,routing:routingState}' \
  -o json | tee "$EVIDENCE_DIR/virtual-hub-status.json"
for connection_id in "$CUSTOMER_WORKLOAD_CONNECTION_ID" "$ISV_HUB_CONNECTION_ID"; do
  if ! az network vhub connection show \
    --ids "$connection_id" \
    --query '{id:id,state:provisioningState,routing:routingConfiguration}' \
    -o json | tee "$EVIDENCE_DIR/${connection_id##*/}-status.json"; then
    printf 'ERROR: Cannot inspect connection %s. Check Azure access and whether its deployment completed.\n' "$connection_id" >&2
    break
  fi
done
```

Require hub provisioning `Succeeded`, routing `Provisioned`, and both connections `Succeeded`. Inspect the load balancer's **Health Probe Status** metric and VM extension state as described in [deployment stage 1](../README.md#1-isv-core).

If a probe is unhealthy, run **in the remote NVA SSH session**:

```zsh
cloud-init status --long
systemctl status forwarding-health.socket
```

### Traffic fails or bypasses the NVA

Run locally:

```zsh
./scripts/show-effective-routes.sh \
  --virtual-hub-id "$VIRTUAL_HUB_ID" \
  --customer-nic-id "$CUSTOMER_WORKLOAD_NIC_ID" \
  --isv-nic-id "$ISV_WORKLOAD_NIC_ID" \
  --nva-nic-id "$NVA_1_NIC_ID" \
  2>&1 | tee "$EVIDENCE_DIR/effective-routes.txt"
```

The helper runs its own Bash interpreter; it can be invoked from Zsh. It inspects `defaultRouteTable`, matching the demo. Repeat for additional NVA NICs if needed. Check the ISV workload's customer-prefix UDR uses `NVA_LOAD_BALANCER_FRONTEND_IP`, the NVA has a customer route through the hub, and the connection static route has the configured ISV destination. Do not attach the workload return-path UDR to the NVA subnet.

For structured route evidence:

```zsh
az network vhub get-effective-routes \
  --ids "$VIRTUAL_HUB_ID" \
  --resource-type RouteTable \
  --resource-id "$DEFAULT_HUB_ROUTE_TABLE_ID" \
  -o json > "$EVIDENCE_DIR/virtual-hub-effective-routes.json"
for nic_id in "$CUSTOMER_WORKLOAD_NIC_ID" "$ISV_WORKLOAD_NIC_ID" "${NVA_NIC_IDS[@]}"; do
  if ! az network nic show-effective-route-table \
    --ids "$nic_id" \
    -o json > "$EVIDENCE_DIR/${nic_id##*/}-routes.json"; then
    printf 'ERROR: Cannot inspect routes for NIC %s. Check that the VM is running and you can read the NIC.\n' "$nic_id" >&2
    break
  fi
done
```

Routes support packet evidence; they do not replace it. If SSH fails, check Bastion tunneling, subscription/user/key selection, and subnet NSGs. If `nc` or `tcpdump` is missing on a VM, investigate its cloud-init/extension failure rather than treating the flow as verified.

### Firewall logs are missing

Skip these diagnostics when Firewall is disabled. Run locally:

```zsh
az network firewall show \
  --ids "$CUSTOMER_FIREWALL_ID" \
  -o json > "$EVIDENCE_DIR/customer-firewall-status.json"
az resource show \
  --ids "$CUSTOMER_FIREWALL_ROUTING_INTENT_ID" \
  -o json > "$EVIDENCE_DIR/customer-firewall-routing-intent.json"
az feature show \
  --namespace Microsoft.Network \
  --name AFWEnableTcpConnectionLogging \
  --query properties.state \
  -o tsv
```

Flow Trace requires the feature state `Registered`. Have the subscription owner enable it using the [Flow Trace procedure](https://learn.microsoft.com/azure/firewall/monitor-firewall-reference#flow-trace). Network-rule logs are useful without Flow Trace. An API permission error is not evidence that the feature is disabled.

If the CLI query command is unavailable, install its extension:

```zsh
az extension add --name log-analytics --allow-preview true
```

Check diagnostics, ingestion delay, query errors, and actual Routing Intent before interpreting an empty result as a path decision.

## Cleanup

Retain evidence until reviewed, then follow the single [teardown procedure](../README.md#destroy). Do not remove local state until all six resource groups and their resources are confirmed gone.
