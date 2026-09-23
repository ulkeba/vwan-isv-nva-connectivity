# Verification runbook

This is a linear copy/paste runbook for proving route convergence, NVA
traversal, source-address preservation, and single-NVA failover.

## Prerequisites

Install `jq`, Terraform, Azure CLI, and OpenSSH. Sign in with `az login`, apply
all four Terraform roots, and make sure the demo SSH private key is readable.

On Ubuntu or WSL, install `jq` with:

```bash
sudo apt-get update
sudo apt-get install -y jq
```

Run **every command below from the repository root in one ongoing interactive
shell**. Do not change shells partway through: `environment.sh` is sourced once
and its variables are used by all later commands.

## 1. Capture deployment outputs and load variables

The four JSON files are the initial deployment evidence. `environment.sh`
reads these exact paths with `jq`.

```bash
test -f ./environment.sh
test -x ./scripts/show-effective-routes.sh
test -x ./scripts/show-nva-counters.sh
test -x ./scripts/test-connectivity.sh
command -v jq
mkdir -p evidence

terraform -chdir=01-isv-core output -json > evidence/01-isv-core.json
terraform -chdir=02-customer-core output -json > evidence/02-customer-core.json
terraform -chdir=03-isv-routing output -json > evidence/03-isv-routing.json
terraform -chdir=04-customer-connection output -json > evidence/04-customer-connection.json

source ./environment.sh
test -r "$SSH_KEY"
```

Values that only exist in the live Azure resources can be added explicitly
after sourcing:

```bash
export ISV_ADMIN_USERNAME="$(az vm show \
  --ids "$ISV_WORKLOAD_VM_ID" \
  --query osProfile.adminUsername \
  --output tsv)"
export CUSTOMER_ADMIN_USERNAME="$(az vm show \
  --ids "$CUSTOMER_WORKLOAD_VM_ID" \
  --query osProfile.adminUsername \
  --output tsv)"

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

When `virtual_hub_deploy_firewall` is enabled, capture the firewall identifiers
and provisioning state:

```bash
export CUSTOMER_FIREWALL_ID="$(jq -er \
  '.customer_virtual_hub_firewall.value.firewall_id' \
  "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_FIREWALL_ROUTING_INTENT_ID="$(jq -er \
  '.customer_virtual_hub_firewall.value.routing_intent_id' \
  "$EVIDENCE_DIR/02-customer-core.json")"

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

With Azure Firewall enabled, also confirm that only the customer workload NIC
learns `0.0.0.0/0` through Azure Firewall. The customer route for
`10.100.1.0/24` and the ISV route for `10.10.0.0/16` must still use the NVA
path. Stop if either private prefix resolves to Azure Firewall.

## 4. Capture counters, then test both directions

Capture the baseline NVA counters. The helper owns the Bastion tunnel details.

```bash
./scripts/show-nva-counters.sh \
  --bastion-name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --admin-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --nva-vm-id "$NVA_1_VM_ID" \
  --nva-vm-id "$NVA_2_VM_ID" \
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
  --nva-vm-id "$NVA_1_VM_ID" \
  --nva-vm-id "$NVA_2_VM_ID" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/nva-counters-after.txt"
```

Successful raw TCP checks on port 2000, destination-observed source addresses,
and increasing NVA counters are the authoritative result. No HTTP protocol is
used. ICMP is only supporting evidence.

## 5. Prove NVA 1 failover (disruptive)

> **WARNING:** These commands stop NVA 1. Never stop both NVAs. There is no
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

Capture counters and confirm NVA 2 handled the failover traffic:

```bash
./scripts/show-nva-counters.sh \
  --bastion-name "$ISV_BASTION_NAME" \
  --resource-group "$ISV_RESOURCE_GROUP" \
  --admin-username "$ISV_ADMIN_USERNAME" \
  --ssh-key "$SSH_KEY" \
  --nva-vm-id "$NVA_1_VM_ID" \
  --nva-vm-id "$NVA_2_VM_ID" \
  --subscription "$AZURE_SUBSCRIPTION" \
  | tee "$EVIDENCE_DIR/nva-counters-after-failover.txt"
```

## 6. Observe forwarded traffic interactively (disruptive)

This test stops NVA 2 so the load balancer must select NVA 1. You then open
three interactive SSH sessions:

1. NVA 1, running `tcpdump`.
2. The ISV workload VM, listening on raw TCP port 2000.
3. The customer workload VM, sending a short message to that listener.

> **WARNING:** Never stop both NVAs. There is no automatic restoration if a
> terminal closes or a command is interrupted. Copy the NVA 2 restore command
> below somewhere accessible before starting.

**NVA 2 restore command:**

```bash
az vm start \
  --ids "$NVA_2_VM_ID"
```

Ensure NVA 1 is running before stopping NVA 2:

```bash
az vm start \
  --ids "$NVA_1_VM_ID"
az vm wait \
  --ids "$NVA_1_VM_ID" \
  --updated \
  --custom "instanceView.statuses[?code=='PowerState/running']"
```

Stop NVA 2 and wait for Azure to report it stopped:

```bash
az vm stop \
  --ids "$NVA_2_VM_ID"
az vm wait \
  --ids "$NVA_2_VM_ID" \
  --updated \
  --custom "instanceView.statuses[?code=='PowerState/stopped']"
az vm get-instance-view \
  --ids "$NVA_2_VM_ID" \
  --output json > "$EVIDENCE_DIR/interactive-nva-2-stopped.json"
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
  'host 10.10.1.10 and host 10.100.1.4 and tcp port 2000'
```

Leave `tcpdump` running. Press `Ctrl+C` after the message has been sent.

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
echo 'hello-through-nva' | nc -w 3 10.100.1.4 2000
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
eth0 In  IP 10.10.1.10.54321 > 10.100.1.4.2000: Flags [S]
eth0 Out IP 10.10.1.10.54321 > 10.100.1.4.2000: Flags [S]
eth0 In  IP 10.100.1.4.2000 > 10.10.1.10.54321: Flags [S.]
eth0 In  IP 10.10.1.10.54321 > 10.100.1.4.2000: Flags [P.], length 18
```

Because the capture uses interface `any`, Linux may show both `In` and `Out`
metadata lines for the same forwarded packet. These addresses still prove that
NVA 1 forwarded the connection without SNAT. Press `Ctrl+C` to stop `tcpdump`
and netcat, then close the three SSH sessions.

**Restore NVA 2 now:**

```bash
az vm start \
  --ids "$NVA_2_VM_ID"
az vm wait \
  --ids "$NVA_2_VM_ID" \
  --updated \
  --custom "instanceView.statuses[?code=='PowerState/running']"
az vm get-instance-view \
  --ids "$NVA_2_VM_ID" \
  --output json > "$EVIDENCE_DIR/interactive-nva-2-restored.json"
```

Wait for the NVA 2 load-balancer probe to recover before continuing.

## 7. Negative controls (optional and destructive)

> **STRONG WARNING:** Each control intentionally destroys managed routing
> resources and interrupts connectivity. Run only in an approved maintenance
> window. Run only one control at a time. There is no automatic restoration
> after interruption. The commands are interactive and intentionally omit
> `-auto-approve`; read every Terraform prompt before approving. These examples
> assume the deployment used `demo.tfvars`.

### Remove and restore the ISV return-path route

Destroy the route layer:

```bash
terraform -chdir=03-isv-routing destroy \
  -input=true \
  -no-color \
  -var-file=demo.tfvars \
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
  -var-file=demo.tfvars \
  | tee "$EVIDENCE_DIR/negative-udr-restore.txt"
```

### Remove and restore the customer-managed ISV connection

Destroy the connection layer:

```bash
terraform -chdir=04-customer-connection destroy \
  -input=true \
  -no-color \
  -var-file=demo.tfvars \
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
  -var-file=demo.tfvars \
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
  -input=true -var-file=demo.tfvars
terraform -chdir=03-isv-routing destroy \
  -input=true -var-file=demo.tfvars
terraform -chdir=02-customer-core destroy \
  -input=true -var-file=demo.tfvars
terraform -chdir=01-isv-core destroy \
  -input=true -var-file=demo.tfvars
```

Confirm that both resource groups and all billable Public IP, Bastion, disk,
load-balancer, and Virtual WAN resources are gone. Remove local evidence only
after it has been archived:

```bash
printf 'Evidence directory retained at: %s\n' "$EVIDENCE_DIR"
rm -ri -- "$EVIDENCE_DIR"
```
