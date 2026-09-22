#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  show-nva-counters.sh --bastion-name NAME --resource-group GROUP \
    --admin-username USER --ssh-key FILE --nva-vm-id ID [--nva-vm-id ID ...] \
    [--subscription ID_OR_NAME] [--local-port-base PORT]

Opens native Azure Bastion tunnels and prints each NVA's forwarding rules,
packet/byte counters, interface counters, and forwarding state.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

bastion_name=
resource_group=
admin_username=
ssh_key=
subscription=
local_port_base=51022
nva_vm_ids=()
tunnel_pids=()
tunnel_logs=()
known_hosts_file=$(mktemp)

cleanup() {
  local pid
  for pid in "${tunnel_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  local log
  for log in "${tunnel_logs[@]}"; do
    rm -f "$log"
  done
  rm -f "$known_hosts_file"
}
trap cleanup EXIT INT TERM

while (($#)); do
  case "$1" in
    --bastion-name|--resource-group|--admin-username|--ssh-key|--nva-vm-id|--subscription|--local-port-base)
      (($# >= 2)) || die "$1 requires a value"
      case "$1" in
        --bastion-name) bastion_name=$2 ;;
        --resource-group) resource_group=$2 ;;
        --admin-username) admin_username=$2 ;;
        --ssh-key) ssh_key=$2 ;;
        --nva-vm-id) nva_vm_ids+=("$2") ;;
        --subscription) subscription=$2 ;;
        --local-port-base) local_port_base=$2 ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n $bastion_name ]] || die "missing --bastion-name"
[[ -n $resource_group ]] || die "missing --resource-group"
[[ -n $admin_username ]] || die "missing --admin-username"
[[ -n $ssh_key ]] || die "missing --ssh-key"
[[ -r $ssh_key ]] || die "SSH key is not readable: $ssh_key"
((${#nva_vm_ids[@]} > 0)) || die "at least one --nva-vm-id is required"
[[ $local_port_base =~ ^[0-9]+$ ]] &&
  ((local_port_base >= 1024 && local_port_base + ${#nva_vm_ids[@]} <= 65535)) ||
  die "--local-port-base must provide enough ports in the range 1024-65535"

command -v az >/dev/null 2>&1 || die "Azure CLI (az) is not installed"
command -v ssh >/dev/null 2>&1 || die "native OpenSSH client (ssh) is not installed"
az account show --only-show-errors -o none >/dev/null 2>&1 ||
  die "Azure CLI is not authenticated; run 'az login'"

az_common=(--only-show-errors)
[[ -n $subscription ]] && az_common+=(--subscription "$subscription")
ssh_common=(-i "$ssh_key" -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$known_hosts_file")

wait_for_tunnel() {
  local port=$1
  local pid=$2
  local log=$3
  local attempt

  for attempt in {1..30}; do
    kill -0 "$pid" 2>/dev/null || {
      cat "$log" >&2
      return 1
    }
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      exec 3>&-
      return 0
    fi
    sleep 1
  done
  printf 'Tunnel did not become ready on local port %s\n' "$port" >&2
  cat "$log" >&2
  return 1
}

for index in "${!nva_vm_ids[@]}"; do
  vm_id=${nva_vm_ids[$index]}
  [[ $vm_id == /subscriptions/* ]] || die "--nva-vm-id must be an Azure resource ID: $vm_id"
  port=$((local_port_base + index))
  log="${XDG_RUNTIME_DIR:-$HOME/.cache}/fd-fwaas-bastion-$BASHPID-$index.log"
  mkdir -p "${log%/*}"
  tunnel_logs+=("$log")

  az network bastion tunnel \
    --name "$bastion_name" \
    --resource-group "$resource_group" \
    --target-resource-id "$vm_id" \
    --resource-port 22 \
    --port "$port" \
    "${az_common[@]}" >"$log" 2>&1 &
  tunnel_pids+=("$!")
  wait_for_tunnel "$port" "${tunnel_pids[-1]}" "$log" ||
    die "failed to open Bastion tunnel for $vm_id"

  printf '\n=== NVA %d ===\n' "$((index + 1))"
  printf 'VM: %s\nEvidence timestamp (UTC): %s\n' "$vm_id" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  ssh "${ssh_common[@]}" -p "$port" "$admin_username@127.0.0.1" \
    'printf "Host: "; hostname; printf "IPv4 forwarding: "; cat /proc/sys/net/ipv4/ip_forward; printf "\n--- nftables forwarding counters ---\n"; sudo nft -a list ruleset; printf "\n--- interface packet counters ---\n"; ip -s -br link' ||
    die "could not read counters from $vm_id through Bastion"
done

printf '\nCapture this timestamped baseline before and after each directional test and compare nftables packet/byte counters.\n'
