#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  test-connectivity.sh --direction customer-to-isv|isv-to-customer \
    --source-bastion-name NAME --source-resource-group GROUP \
    --source-vm-id ID --source-username USER --ssh-key FILE \
    --destination-ip IP [--expected-source-ip IP] [--tcp-port PORT] \
    [--subscription ID_OR_NAME] [--local-port PORT]

Optional definitive source-preservation observer (all four are required together):
    --destination-bastion-name NAME --destination-resource-group GROUP \
    --destination-vm-id ID --destination-username USER \
    [--destination-local-port PORT]

Without destination observer arguments, the script proves bidirectional ICMP/TCP
reachability and records the expected source. With them, a one-shot TCP observer
on the destination reports and verifies the source address it actually sees.
The default raw TCP test port is 2000.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

direction=
source_bastion_name=
source_resource_group=
source_vm_id=
source_username=
ssh_key=
destination_ip=
expected_source_ip=
tcp_port=2000
subscription=
local_port=52022
destination_bastion_name=
destination_resource_group=
destination_vm_id=
destination_username=
destination_local_port=52023
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
  for log in "${tunnel_logs[@]}"; do rm -f "$log"; done
  rm -f "$known_hosts_file"
}
trap cleanup EXIT INT TERM

while (($#)); do
  case "$1" in
    --direction|--source-bastion-name|--source-resource-group|--source-vm-id|--source-username|--ssh-key|--destination-ip|--expected-source-ip|--tcp-port|--subscription|--local-port|--destination-bastion-name|--destination-resource-group|--destination-vm-id|--destination-username|--destination-local-port)
      (($# >= 2)) || die "$1 requires a value"
      case "$1" in
        --direction) direction=$2 ;;
        --source-bastion-name) source_bastion_name=$2 ;;
        --source-resource-group) source_resource_group=$2 ;;
        --source-vm-id) source_vm_id=$2 ;;
        --source-username) source_username=$2 ;;
        --ssh-key) ssh_key=$2 ;;
        --destination-ip) destination_ip=$2 ;;
        --expected-source-ip) expected_source_ip=$2 ;;
        --tcp-port) tcp_port=$2 ;;
        --subscription) subscription=$2 ;;
        --local-port) local_port=$2 ;;
        --destination-bastion-name) destination_bastion_name=$2 ;;
        --destination-resource-group) destination_resource_group=$2 ;;
        --destination-vm-id) destination_vm_id=$2 ;;
        --destination-username) destination_username=$2 ;;
        --destination-local-port) destination_local_port=$2 ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ $direction == customer-to-isv || $direction == isv-to-customer ]] ||
  die "--direction must be customer-to-isv or isv-to-customer"
for required in source_bastion_name source_resource_group source_vm_id source_username ssh_key destination_ip; do
  [[ -n ${!required} ]] || die "missing --${required//_/-}"
done
[[ $source_vm_id == /subscriptions/* ]] || die "--source-vm-id must be an Azure resource ID"
[[ -r $ssh_key ]] || die "SSH key is not readable: $ssh_key"
[[ $destination_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "--destination-ip must be an IPv4 address"
for port_name in tcp_port local_port destination_local_port; do
  [[ ${!port_name} =~ ^[0-9]+$ ]] && ((${!port_name} >= 1 && ${!port_name} <= 65535)) ||
    die "--${port_name//_/-} must be in the range 1-65535"
done
((local_port != destination_local_port)) || die "source and destination local ports must differ"

observer_values=("$destination_bastion_name" "$destination_resource_group" "$destination_vm_id" "$destination_username")
observer_count=0
for value in "${observer_values[@]}"; do [[ -n $value ]] && ((observer_count += 1)); done
((observer_count == 0 || observer_count == 4)) ||
  die "all destination observer arguments must be supplied together"
if ((observer_count == 4)); then
  [[ $destination_vm_id == /subscriptions/* ]] || die "--destination-vm-id must be an Azure resource ID"
fi

command -v az >/dev/null 2>&1 || die "Azure CLI (az) is not installed"
command -v ssh >/dev/null 2>&1 || die "native OpenSSH client (ssh) is not installed"
az account show --only-show-errors -o none >/dev/null 2>&1 ||
  die "Azure CLI is not authenticated; run 'az login'"

az_common=(--only-show-errors)
[[ -n $subscription ]] && az_common+=(--subscription "$subscription")
ssh_common=(-i "$ssh_key" -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$known_hosts_file")

if [[ -z $expected_source_ip ]]; then
  expected_source_ip=$(az vm show -d --ids "$source_vm_id" --only-show-errors --query privateIps -o tsv)
  expected_source_ip=${expected_source_ip%%,*}
  [[ -n $expected_source_ip ]] || die "could not determine source VM private IP; pass --expected-source-ip"
fi

open_tunnel() {
  local bastion=$1 group=$2 vm_id=$3 port=$4 label=$5
  local log="${XDG_RUNTIME_DIR:-$HOME/.cache}/fd-fwaas-$label-$BASHPID.log"
  local attempt

  mkdir -p "${log%/*}"
  tunnel_logs+=("$log")
  az network bastion tunnel --name "$bastion" --resource-group "$group" \
    --target-resource-id "$vm_id" --resource-port 22 --port "$port" \
    "${az_common[@]}" >"$log" 2>&1 &
  tunnel_pids+=("$!")

  for attempt in {1..30}; do
    kill -0 "${tunnel_pids[-1]}" 2>/dev/null || {
      cat "$log" >&2
      return 1
    }
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      exec 3>&-
      return 0
    fi
    sleep 1
  done
  cat "$log" >&2
  return 1
}

start_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
printf '=== Connectivity evidence ===\n'
printf 'Start (UTC): %s\nDirection: %s\nExpected original source: %s\nDestination: %s\n' \
  "$start_utc" "$direction" "$expected_source_ip" "$destination_ip"

open_tunnel "$source_bastion_name" "$source_resource_group" "$source_vm_id" "$local_port" source ||
  die "failed to open source Bastion tunnel"

if ((observer_count == 4)); then
  open_tunnel "$destination_bastion_name" "$destination_resource_group" \
    "$destination_vm_id" "$destination_local_port" destination ||
    die "failed to open destination Bastion tunnel"

  observer_command="python3 -c 'import socket,sys; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind((\"0.0.0.0\",int(sys.argv[1]))); s.listen(1); s.settimeout(30); c,a=s.accept(); message=\"DESTINATION_OBSERVED_SOURCE=\"+a[0]; print(message,flush=True); c.sendall((message+\"\\n\").encode()); c.close(); s.close()' '$tcp_port'"
  coproc DESTINATION_OBSERVER {
    ssh "${ssh_common[@]}" -p "$destination_local_port" \
      "$destination_username@127.0.0.1" "$observer_command"
  }
  destination_observer_pid=$DESTINATION_OBSERVER_PID
  sleep 1
  tcp_mode=observe
else
  tcp_mode=connect
  printf 'Source observer: not requested (pass destination observer arguments for definitive source-IP proof)\n'
fi

set +e
test_output=$(ssh "${ssh_common[@]}" -p "$local_port" "$source_username@127.0.0.1" \
  bash -s -- "$destination_ip" "$tcp_port" "$tcp_mode" <<'REMOTE'
set -euo pipefail
destination=$1
port=$2
mode=$3
printf '%s\n' '--- ICMP ---'
if ping -n -c 4 -W 3 "$destination"; then
  printf '%s\n' 'ICMP_RESULT=PASS'
else
  printf '%s\n' 'ICMP_RESULT=FAIL (best-effort; TCP remains authoritative)'
fi
printf '%s\n' '--- TCP ---'
python3 - "$destination" "$port" "$mode" <<'PY'
import socket
import sys

destination, port, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
with socket.create_connection((destination, port), timeout=8) as connection:
    print(f"TCP_CONNECT_SUCCESS={destination}:{port}")
    if mode == "observe":
        connection.settimeout(8)
        print(connection.recv(256).decode().strip())
PY
REMOTE
)
test_status=$?
set -e
printf '%s\n' "$test_output"
((test_status == 0)) || die "TCP test failed"

if ((observer_count == 4)); then
  wait "$destination_observer_pid" || die "destination observer failed"
  observed_source=$(sed -n 's/^DESTINATION_OBSERVED_SOURCE=//p' <<<"$test_output" | tail -n 1)
  [[ -n $observed_source ]] || die "destination did not report the observed source"
  [[ $observed_source == "$expected_source_ip" ]] ||
    die "source preservation failed: destination saw $observed_source, expected $expected_source_ip"
  printf 'Source preservation: PASS (destination observed %s)\n' "$observed_source"
else
  printf 'Source preservation: NOT DIRECTLY OBSERVED (expected %s)\n' "$expected_source_ip"
fi

printf 'End (UTC): %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf 'Run the opposite --direction independently and compare timestamped NVA counters before/after each run.\n'
