#!/usr/bin/env bash
# Lab t1-08 cleanup (idempotent).
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
cluster_exists || { ok "no cluster - nothing to clean"; exit 0; }
NS="$LAB_NAMESPACE"

if k get crd "$CRD_NAME" >/dev/null 2>&1; then
  step "Remove finalizers from lab VMRequests" \
       "an object with a finalizer and no controller to clear it would block namespace deletion forever"
  for r in $(k -n "$NS" get vmrequests -o name 2>/dev/null); do
    k -n "$NS" patch "$r" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null
  done
  ok "finalizers cleared"
fi

step "Delete namespace $NS" "removes VMRequests and the ConfigMaps the controller created"
delete_ns "$NS"

step "Delete the CRD $CRD_NAME" "CRDs are cluster-scoped; deleting one also deletes all its objects"
k delete crd "$CRD_NAME" --ignore-not-found >/dev/null
ok "cleanup complete (stop ./controller.sh with Ctrl+C if it is still running)"
