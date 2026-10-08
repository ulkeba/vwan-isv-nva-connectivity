#!/usr/bin/env bash

# Set matching DEPLOYMENT_NAME and TF_WORKSPACE values, then source this file
# from the repository root after capturing the Terraform output JSON files.

if test -z "${BASH_VERSION:-}" && test -z "${ZSH_VERSION:-}"; then
  printf '[environment] ERROR: Source environment.sh from Bash or zsh.\n' >&2
  return 1
fi

environment_debug() {
  case "${ENVIRONMENT_DEBUG:-0}" in
    1|true|TRUE|yes|YES)
      printf '[environment] %s\n' "$*" >&2
      ;;
  esac
}

environment_error() {
  printf '[environment] ERROR: %s\n' "$*" >&2
}

environment_require_file() {
  if ! test -s "$1"; then
    environment_error "Required evidence file is missing or empty: $1"
    return 1
  fi

  environment_debug "Found evidence file: $1"
}

environment_validate_json() {
  local description="$1"
  local file="$2"
  local filter="$3"

  environment_debug "Validating $description in $file"
  if ! jq -e "$filter" "$file" >/dev/null; then
    environment_error "Validation failed for $description in $file"
    return 1
  fi
}

command -v jq >/dev/null || {
  environment_error 'jq is required. Install it before sourcing environment.sh.'
  return 1
}

if test -z "${DEPLOYMENT_NAME:-}"; then
  environment_error 'DEPLOYMENT_NAME is required before sourcing environment.sh.'
  return 1
fi

if [[ ! "$DEPLOYMENT_NAME" =~ ^[[:alnum:]][[:alnum:]_-]*$ ]]; then
  environment_error "DEPLOYMENT_NAME contains unsupported characters: $DEPLOYMENT_NAME"
  return 1
fi

if test -z "${TF_WORKSPACE:-}"; then
  environment_error 'TF_WORKSPACE is required before sourcing environment.sh.'
  return 1
fi

if test "$TF_WORKSPACE" != "$DEPLOYMENT_NAME"; then
  environment_error "TF_WORKSPACE must match DEPLOYMENT_NAME: $TF_WORKSPACE != $DEPLOYMENT_NAME"
  return 1
fi

for environment_root in \
  01-isv-core \
  02-customer-core \
  03-isv-routing \
  04-customer-connection; do
  if ! test -s "$environment_root/$DEPLOYMENT_NAME.tfvars"; then
    environment_error "Deployment tfvars file is missing or empty: $environment_root/$DEPLOYMENT_NAME.tfvars"
    return 1
  fi
done
unset environment_root

export DEPLOYMENT_NAME TF_WORKSPACE
export EVIDENCE_DIR="${EVIDENCE_DIR:-evidence_$DEPLOYMENT_NAME}"
export SSH_KEY="${SSH_KEY:-$HOME/.ssh/fd-fwaas-demo}"

environment_debug "Loading $DEPLOYMENT_NAME environment from $EVIDENCE_DIR"
environment_debug "Using SSH key path $SSH_KEY"

environment_status=0

if environment_require_file "$EVIDENCE_DIR/01-isv-core.json"; then
  if environment_validate_json 'ISV core outputs' "$EVIDENCE_DIR/01-isv-core.json" '
    ((.nva_virtual_machines.value | length) >= 1 and (.nva_virtual_machines.value | length) <= 3) and
    ([
      .isv_virtual_network.value.resource_group,
      .isv_bastion.value.name,
      .isv_workload_virtual_machine.value.id,
      .isv_workload_virtual_machine.value.nic_id,
      .isv_workload_virtual_machine.value.private_ip_address,
      .isv_workload_virtual_machine.value.admin_username,
      .isv_workload_subnet.value.address_prefixes[0],
      .nva_load_balancer.value.id,
      .nva_load_balancer.value.frontend_ip
    ] | all(. != null and . != "")) and
    ([.nva_virtual_machines.value[] | .id, .nic_id, .private_ip] | all(. != null and . != ""))
  '; then
    environment_debug 'Exporting ISV core variables'
    export ISV_RESOURCE_GROUP="$(jq -er '.isv_bastion.value.resource_group' "$EVIDENCE_DIR/01-isv-core.json")"
    export ISV_BASTION_NAME="$(jq -er '.isv_bastion.value.name' "$EVIDENCE_DIR/01-isv-core.json")"
    export ISV_WORKLOAD_VM_ID="$(jq -er '.isv_workload_virtual_machine.value.id' "$EVIDENCE_DIR/01-isv-core.json")"
    export ISV_WORKLOAD_NIC_ID="$(jq -er '.isv_workload_virtual_machine.value.nic_id' "$EVIDENCE_DIR/01-isv-core.json")"
    export ISV_WORKLOAD_PRIVATE_IP="$(jq -er '.isv_workload_virtual_machine.value.private_ip_address' "$EVIDENCE_DIR/01-isv-core.json")"
    export ISV_ADMIN_USERNAME="$(jq -er '.isv_workload_virtual_machine.value.admin_username' "$EVIDENCE_DIR/01-isv-core.json")"
    export ISV_WORKLOAD_PREFIX="$(jq -er '.isv_workload_subnet.value.address_prefixes[0]' "$EVIDENCE_DIR/01-isv-core.json")"
    export NVA_LOAD_BALANCER_ID="$(jq -er '.nva_load_balancer.value.id' "$EVIDENCE_DIR/01-isv-core.json")"
    export NVA_LOAD_BALANCER_FRONTEND_IP="$(jq -er '.nva_load_balancer.value.frontend_ip' "$EVIDENCE_DIR/01-isv-core.json")"

    unset NVA_NAMES NVA_VM_IDS NVA_NIC_IDS NVA_PRIVATE_IPS
    unset NVA_1_NAME NVA_1_VM_ID NVA_1_NIC_ID NVA_1_PRIVATE_IP
    unset NVA_2_NAME NVA_2_VM_ID NVA_2_NIC_ID NVA_2_PRIVATE_IP
    unset NVA_3_NAME NVA_3_VM_ID NVA_3_NIC_ID NVA_3_PRIVATE_IP

    if ! nva_names="$(jq -er '.nva_virtual_machines.value | keys[]' "$EVIDENCE_DIR/01-isv-core.json")"; then
      environment_error 'Could not read NVA names from ISV core outputs.'
      return 1
    fi

    NVA_NAMES=()
    NVA_VM_IDS=()
    NVA_NIC_IDS=()
    NVA_PRIVATE_IPS=()

    nva_number=0
    while IFS= read -r nva_name; do
      nva_number=$((nva_number + 1))
      nva_vm_id="$(jq -er --arg name "$nva_name" '.nva_virtual_machines.value[$name].id' "$EVIDENCE_DIR/01-isv-core.json")"
      nva_nic_id="$(jq -er --arg name "$nva_name" '.nva_virtual_machines.value[$name].nic_id' "$EVIDENCE_DIR/01-isv-core.json")"
      nva_private_ip="$(jq -er --arg name "$nva_name" '.nva_virtual_machines.value[$name].private_ip' "$EVIDENCE_DIR/01-isv-core.json")"

      NVA_NAMES+=("$nva_name")
      NVA_VM_IDS+=("$nva_vm_id")
      NVA_NIC_IDS+=("$nva_nic_id")
      NVA_PRIVATE_IPS+=("$nva_private_ip")

      export "NVA_${nva_number}_NAME=$nva_name" "NVA_${nva_number}_VM_ID=$nva_vm_id"
      export "NVA_${nva_number}_NIC_ID=$nva_nic_id" "NVA_${nva_number}_PRIVATE_IP=$nva_private_ip"
    done <<< "$nva_names"
    export NVA_COUNT="$nva_number"
    unset nva_names nva_number nva_name nva_vm_id nva_nic_id nva_private_ip
  else
    environment_status=1
  fi
else
  environment_status=1
fi

if environment_require_file "$EVIDENCE_DIR/02-customer-core.json"; then
  if environment_validate_json 'customer core outputs' "$EVIDENCE_DIR/02-customer-core.json" '
    ([
      .customer_bastion.value.resource_group,
      .customer_bastion.value.name,
      .customer_workload_virtual_machine.value.id,
      .customer_workload_virtual_machine.value.nic_id,
      .customer_workload_virtual_machine.value.private_ip_address,
      .customer_workload_virtual_machine.value.admin_username,
      .customer_virtual_network.value.address_spaces[0],
      .customer_virtual_hub.value.id,
      .customer_virtual_hub.value.default_route_table_id,
      .customer_workload_connection.value.id
    ] | all(. != null and . != "")) and
    (
      (
        .customer_virtual_hub_firewall.value == null and
        .customer_firewall_log_analytics_workspace.value == null
      ) or
      (
        .customer_virtual_hub_firewall.value != null and
        ([
          .customer_virtual_hub_firewall.value.firewall_id,
          .customer_virtual_hub_firewall.value.routing_intent_id,
          .customer_firewall_log_analytics_workspace.value.id,
          .customer_firewall_log_analytics_workspace.value.workspace_id
        ] | all(. != null and . != ""))
      )
    )
  '; then
    environment_debug 'Exporting customer core variables'
    export CUSTOMER_RESOURCE_GROUP="$(jq -er '.customer_bastion.value.resource_group' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_BASTION_NAME="$(jq -er '.customer_bastion.value.name' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_WORKLOAD_VM_ID="$(jq -er '.customer_workload_virtual_machine.value.id' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_WORKLOAD_NIC_ID="$(jq -er '.customer_workload_virtual_machine.value.nic_id' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_WORKLOAD_PRIVATE_IP="$(jq -er '.customer_workload_virtual_machine.value.private_ip_address' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_ADMIN_USERNAME="$(jq -er '.customer_workload_virtual_machine.value.admin_username' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_VNET_PREFIX="$(jq -er '.customer_virtual_network.value.address_spaces[0]' "$EVIDENCE_DIR/02-customer-core.json")"
    export VIRTUAL_HUB_ID="$(jq -er '.customer_virtual_hub.value.id' "$EVIDENCE_DIR/02-customer-core.json")"
    export DEFAULT_HUB_ROUTE_TABLE_ID="$(jq -er '.customer_virtual_hub.value.default_route_table_id' "$EVIDENCE_DIR/02-customer-core.json")"
    export CUSTOMER_WORKLOAD_CONNECTION_ID="$(jq -er '.customer_workload_connection.value.id' "$EVIDENCE_DIR/02-customer-core.json")"
    export AZURE_SUBSCRIPTION="$(jq -er '.customer_virtual_hub.value.id | split("/")[2]' "$EVIDENCE_DIR/02-customer-core.json")"

    if jq -e '.customer_virtual_hub_firewall.value != null' "$EVIDENCE_DIR/02-customer-core.json" >/dev/null; then
      export CUSTOMER_FIREWALL_ID="$(jq -er '.customer_virtual_hub_firewall.value.firewall_id' "$EVIDENCE_DIR/02-customer-core.json")"
      export CUSTOMER_FIREWALL_ROUTING_INTENT_ID="$(jq -er '.customer_virtual_hub_firewall.value.routing_intent_id' "$EVIDENCE_DIR/02-customer-core.json")"
      export CUSTOMER_FIREWALL_LOG_ANALYTICS_WORKSPACE_ID="$(jq -er '.customer_firewall_log_analytics_workspace.value.workspace_id' "$EVIDENCE_DIR/02-customer-core.json")"
    else
      unset CUSTOMER_FIREWALL_ID CUSTOMER_FIREWALL_ROUTING_INTENT_ID CUSTOMER_FIREWALL_LOG_ANALYTICS_WORKSPACE_ID
      environment_debug 'Customer firewall output is not available; firewall variables were unset'
    fi
  else
    environment_status=1
  fi
else
  environment_status=1
fi

if test -s "$EVIDENCE_DIR/03-isv-routing.json"; then
  if environment_validate_json 'ISV routing outputs' "$EVIDENCE_DIR/03-isv-routing.json" '
    [
      .isv_route_table.value.id,
      .isv_route_table.value.route.id
    ] | all(. != null and . != "")
  '; then
    environment_debug 'Exporting ISV routing variables'
    export ISV_ROUTE_TABLE_ID="$(jq -er '.isv_route_table.value.id' "$EVIDENCE_DIR/03-isv-routing.json")"
    export ISV_ROUTE_ID="$(jq -er '.isv_route_table.value.route.id' "$EVIDENCE_DIR/03-isv-routing.json")"
  else
    environment_status=1
  fi
else
  unset ISV_ROUTE_TABLE_ID ISV_ROUTE_ID
  environment_debug "Skipping unavailable stage 03 evidence: $EVIDENCE_DIR/03-isv-routing.json"
fi

if test -s "$EVIDENCE_DIR/04-customer-connection.json"; then
  if environment_validate_json 'customer connection outputs' "$EVIDENCE_DIR/04-customer-connection.json" '
    [
      .isv_hub_connection.value.id
    ] | all(. != null and . != "")
  '; then
    environment_debug 'Exporting customer connection variables'
    export ISV_HUB_CONNECTION_ID="$(jq -er '.isv_hub_connection.value.id' "$EVIDENCE_DIR/04-customer-connection.json")"
  else
    environment_status=1
  fi
else
  unset ISV_HUB_CONNECTION_ID
  environment_debug "Skipping unavailable stage 04 evidence: $EVIDENCE_DIR/04-customer-connection.json"
fi

if test "$environment_status" -eq 0; then
  environment_debug 'Available environment variables loaded successfully'
else
  environment_error 'One or more available evidence stages could not be loaded'
fi

return "$environment_status"
