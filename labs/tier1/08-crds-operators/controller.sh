#!/usr/bin/env bash
# A toy controller for VMRequest objects - about 60 lines of bash, so you can
# read every step. Real controllers (KubeVirt's virt-controller, Harvester's,
# Longhorn's) are Go programs, but they follow exactly this loop:
#
#   1. OBSERVE  the desired state (every VMRequest's spec)
#   2. COMPARE  it with the actual state (does its "VM" exist and match?)
#   3. ACT      to close the gap (create/update the VM, then report status)
#   ...repeat forever. This is "reconciliation".
#
# Our pretend "VM" is a ConfigMap named <request>-vm. Its ownerReference points
# at the VMRequest, so Kubernetes' garbage collector deletes it automatically
# when the VMRequest is deleted - the controller doesn't have to.
#
# Usage: ./controller.sh          run until Ctrl+C
#        ./controller.sh --once   one reconcile pass, then exit
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
NS="$LAB_NAMESPACE"
log() { printf '%s [controller] %s\n' "$(date +%H:%M:%S)" "$*"; }

reconcile_one() {
  local name="$1" uid="$2" cpu="$3" mem="$4" image="$5" phase="$6"
  # ACT (1): make the actual "VM" match the spec. `apply` is idempotent:
  # it prints "unchanged" when reality already matches.
  local out
  out="$(k apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${name}-vm
  namespace: ${NS}
  labels: {app.kubernetes.io/managed-by: vmrequest-controller}
  ownerReferences:
  - apiVersion: lab.example.com/v1alpha1
    kind: VMRequest
    name: ${name}
    uid: ${uid}
    controller: true
    blockOwnerDeletion: true
data:
  cpu: "${cpu}"
  memoryGi: "${mem}"
  image: "${image}"
YAML
)"
  [[ "$out" == *unchanged* ]] || log "$name: $out"
  # ACT (2): report what we did in .status (a separate subresource, so users
  # editing .spec and the controller writing .status never overwrite each other).
  if [[ "$phase" != "Provisioned" ]]; then
    k -n "$NS" patch vmrequest "$name" --subresource=status --type=merge \
      -p "{\"status\":{\"phase\":\"Provisioned\",\"message\":\"VM ${name}-vm has ${cpu} vCPU / ${mem} GiB\"}}" >/dev/null
    log "$name: status -> Provisioned"
  fi
}

reconcile_all() {
  # OBSERVE: list every VMRequest (a real controller uses a watch + cache instead of polling).
  local name uid cpu mem image phase deleting
  while IFS='|' read -r name uid cpu mem image phase deleting; do
    [[ -z "$name" ]] && continue
    if [[ -n "$deleting" ]]; then continue; fi   # being deleted: not our job any more
    reconcile_one "$name" "$uid" "$cpu" "$mem" "$image" "$phase"
  done < <(k -n "$NS" get vmrequests -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.uid}|{.spec.cpu}|{.spec.memoryGi}|{.spec.image}|{.status.phase}|{.metadata.deletionTimestamp}{"\n"}{end}')
}

k get crd "$CRD_NAME" >/dev/null 2>&1 || die "CRD $CRD_NAME not installed yet (Task 2)"
if [[ "${1:-}" == "--once" ]]; then reconcile_all; exit 0; fi
log "watching VMRequests in namespace $NS (Ctrl+C to stop)"
while true; do
  k get crd "$CRD_NAME" >/dev/null 2>&1 || { log "CRD removed - exiting"; exit 0; }
  reconcile_all
  sleep 3
done
