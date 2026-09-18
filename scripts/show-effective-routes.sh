#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  show-effective-routes.sh --virtual-hub-id ID --customer-nic-id ID \
    --isv-nic-id ID --nva-nic-id ID [--subscription ID_OR_NAME]

Shows the Virtual WAN hub and workload/NVA NIC effective routes. Azure CLI
authentication and Reader access to all supplied resources are required.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

virtual_hub_id=
customer_nic_id=
isv_nic_id=
nva_nic_id=
subscription=

while (($#)); do
  case "$1" in
    --virtual-hub-id|--customer-nic-id|--isv-nic-id|--nva-nic-id|--subscription)
      (($# >= 2)) || die "$1 requires a value"
      case "$1" in
        --virtual-hub-id) virtual_hub_id=$2 ;;
        --customer-nic-id) customer_nic_id=$2 ;;
        --isv-nic-id) isv_nic_id=$2 ;;
        --nva-nic-id) nva_nic_id=$2 ;;
        --subscription) subscription=$2 ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

for required in virtual_hub_id customer_nic_id isv_nic_id nva_nic_id; do
  [[ -n ${!required} ]] || die "missing --${required//_/-}"
  [[ ${!required} == /subscriptions/* ]] || die "--${required//_/-} must be an Azure resource ID"
done

command -v az >/dev/null 2>&1 || die "Azure CLI (az) is not installed"
az account show --only-show-errors -o none >/dev/null 2>&1 ||
  die "Azure CLI is not authenticated; run 'az login'"

az_common=(--only-show-errors)
[[ -n $subscription ]] && az_common+=(--subscription "$subscription")

printf 'Evidence timestamp (UTC): %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf 'Virtual hub: %s\n\n' "$virtual_hub_id"

printf '=== Virtual hub effective routes ===\n'
az network vhub get-effective-routes \
  --ids "$virtual_hub_id" \
  --resource-type RouteTable \
  --resource-id "${virtual_hub_id}/hubRouteTables/defaultRouteTable" \
  "${az_common[@]}" \
  --query "value[].{Prefix:join(',', addressPrefixes),NextHopType:nextHopType,NextHops:join(',', nextHops),RouteOrigin:routeOrigin}" \
  -o table ||
  die "could not retrieve virtual hub effective routes (the hub may still be converging)"

show_nic_routes() {
  local label=$1
  local nic_id=$2

  printf '\n=== %s NIC effective routes ===\n' "$label"
  printf 'NIC: %s\n' "$nic_id"
  az network nic show-effective-route-table \
    --ids "$nic_id" \
    "${az_common[@]}" \
    --query "value[].{Prefix:join(',', addressPrefix),NextHopType:nextHopType,NextHopIp:join(',', nextHopIpAddress),Source:source,State:state}" \
    -o table ||
    die "could not retrieve effective routes for $label NIC"
}

show_nic_routes "Customer workload" "$customer_nic_id"
show_nic_routes "ISV workload" "$isv_nic_id"
show_nic_routes "NVA" "$nva_nic_id"

printf '\nCorrelate these routes with bidirectional traffic and NVA counters; routes alone do not prove traversal.\n'
