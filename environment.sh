#!/usr/bin/env bash

# Source this file from the repository root after capturing the four Terraform
# output JSON files documented in docs/verification.md.

command -v jq >/dev/null || {
  printf 'jq is required. Install it before sourcing environment.sh.\n' >&2
  return 1
}

export EVIDENCE_DIR="${EVIDENCE_DIR:-$PWD/evidence}"
export SSH_KEY="${SSH_KEY:-$HOME/.ssh/ecs-vwan-fwaas-demo}"

test -s "$EVIDENCE_DIR/01-isv-core.json" || return 1
test -s "$EVIDENCE_DIR/02-customer-core.json" || return 1
test -s "$EVIDENCE_DIR/03-isv-routing.json" || return 1
test -s "$EVIDENCE_DIR/04-customer-connection.json" || return 1

jq -e '
  [
    .isv_virtual_network.value.resource_group,
    .isv_bastion.value.name,
    .isv_workload_virtual_machine.value.id,
    .isv_workload_virtual_machine.value.nic_id,
    .isv_workload_virtual_machine.value.private_ip_address,
    .isv_workload_subnet.value.address_prefixes[0],
    .nva_load_balancer.value.id,
    .nva_load_balancer.value.frontend_ip,
    .nva_virtual_machines.value["ecs-vwan-isv-nva-1"].id,
    .nva_virtual_machines.value["ecs-vwan-isv-nva-1"].nic_id,
    .nva_virtual_machines.value["ecs-vwan-isv-nva-1"].private_ip,
    .nva_virtual_machines.value["ecs-vwan-isv-nva-2"].id,
    .nva_virtual_machines.value["ecs-vwan-isv-nva-2"].nic_id,
    .nva_virtual_machines.value["ecs-vwan-isv-nva-2"].private_ip
  ] | all(. != null and . != "")
' "$EVIDENCE_DIR/01-isv-core.json" >/dev/null || return 1

jq -e '
  [
    .customer_resource_group.value.name,
    .customer_bastion.value.name,
    .customer_workload_virtual_machine.value.id,
    .customer_workload_virtual_machine.value.nic_id,
    .customer_workload_virtual_machine.value.private_ip_address,
    .customer_virtual_network.value.address_spaces[0],
    .customer_virtual_hub.value.id,
    .customer_virtual_hub.value.default_route_table_id,
    .customer_workload_connection.value.id
  ] | all(. != null and . != "")
' "$EVIDENCE_DIR/02-customer-core.json" >/dev/null || return 1

jq -e '
  [
    .isv_route_table.value.id,
    .isv_route_table.value.route.id
  ] | all(. != null and . != "")
' "$EVIDENCE_DIR/03-isv-routing.json" >/dev/null || return 1

jq -e '
  [
    .isv_hub_connection.value.id
  ] | all(. != null and . != "")
' "$EVIDENCE_DIR/04-customer-connection.json" >/dev/null || return 1

export ISV_RESOURCE_GROUP="$(jq -er '.isv_virtual_network.value.resource_group' "$EVIDENCE_DIR/01-isv-core.json")"
export ISV_BASTION_NAME="$(jq -er '.isv_bastion.value.name' "$EVIDENCE_DIR/01-isv-core.json")"
export ISV_WORKLOAD_VM_ID="$(jq -er '.isv_workload_virtual_machine.value.id' "$EVIDENCE_DIR/01-isv-core.json")"
export ISV_WORKLOAD_NIC_ID="$(jq -er '.isv_workload_virtual_machine.value.nic_id' "$EVIDENCE_DIR/01-isv-core.json")"
export ISV_WORKLOAD_PRIVATE_IP="$(jq -er '.isv_workload_virtual_machine.value.private_ip_address' "$EVIDENCE_DIR/01-isv-core.json")"
export ISV_WORKLOAD_PREFIX="$(jq -er '.isv_workload_subnet.value.address_prefixes[0]' "$EVIDENCE_DIR/01-isv-core.json")"
export NVA_LOAD_BALANCER_ID="$(jq -er '.nva_load_balancer.value.id' "$EVIDENCE_DIR/01-isv-core.json")"
export NVA_LOAD_BALANCER_FRONTEND_IP="$(jq -er '.nva_load_balancer.value.frontend_ip' "$EVIDENCE_DIR/01-isv-core.json")"

export NVA_1_NAME="ecs-vwan-isv-nva-1"
export NVA_1_VM_ID="$(jq -er '.nva_virtual_machines.value["ecs-vwan-isv-nva-1"].id' "$EVIDENCE_DIR/01-isv-core.json")"
export NVA_1_NIC_ID="$(jq -er '.nva_virtual_machines.value["ecs-vwan-isv-nva-1"].nic_id' "$EVIDENCE_DIR/01-isv-core.json")"
export NVA_1_PRIVATE_IP="$(jq -er '.nva_virtual_machines.value["ecs-vwan-isv-nva-1"].private_ip' "$EVIDENCE_DIR/01-isv-core.json")"

export NVA_2_NAME="ecs-vwan-isv-nva-2"
export NVA_2_VM_ID="$(jq -er '.nva_virtual_machines.value["ecs-vwan-isv-nva-2"].id' "$EVIDENCE_DIR/01-isv-core.json")"
export NVA_2_NIC_ID="$(jq -er '.nva_virtual_machines.value["ecs-vwan-isv-nva-2"].nic_id' "$EVIDENCE_DIR/01-isv-core.json")"
export NVA_2_PRIVATE_IP="$(jq -er '.nva_virtual_machines.value["ecs-vwan-isv-nva-2"].private_ip' "$EVIDENCE_DIR/01-isv-core.json")"

export CUSTOMER_RESOURCE_GROUP="$(jq -er '.customer_resource_group.value.name' "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_BASTION_NAME="$(jq -er '.customer_bastion.value.name' "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_WORKLOAD_VM_ID="$(jq -er '.customer_workload_virtual_machine.value.id' "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_WORKLOAD_NIC_ID="$(jq -er '.customer_workload_virtual_machine.value.nic_id' "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_WORKLOAD_PRIVATE_IP="$(jq -er '.customer_workload_virtual_machine.value.private_ip_address' "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_VNET_PREFIX="$(jq -er '.customer_virtual_network.value.address_spaces[0]' "$EVIDENCE_DIR/02-customer-core.json")"
export VIRTUAL_HUB_ID="$(jq -er '.customer_virtual_hub.value.id' "$EVIDENCE_DIR/02-customer-core.json")"
export DEFAULT_HUB_ROUTE_TABLE_ID="$(jq -er '.customer_virtual_hub.value.default_route_table_id' "$EVIDENCE_DIR/02-customer-core.json")"
export CUSTOMER_WORKLOAD_CONNECTION_ID="$(jq -er '.customer_workload_connection.value.id' "$EVIDENCE_DIR/02-customer-core.json")"

export ISV_ROUTE_TABLE_ID="$(jq -er '.isv_route_table.value.id' "$EVIDENCE_DIR/03-isv-routing.json")"
export ISV_ROUTE_ID="$(jq -er '.isv_route_table.value.route.id' "$EVIDENCE_DIR/03-isv-routing.json")"
export ISV_HUB_CONNECTION_ID="$(jq -er '.isv_hub_connection.value.id' "$EVIDENCE_DIR/04-customer-connection.json")"

export AZURE_SUBSCRIPTION="$(jq -er '.customer_virtual_hub.value.id | split("/")[2]' "$EVIDENCE_DIR/02-customer-core.json")"

