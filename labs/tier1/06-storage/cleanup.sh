#!/usr/bin/env bash
# Lab t1-06 cleanup (idempotent). PVs and StorageClasses are cluster-scoped,
# so deleting the namespace is not enough - we remove them explicitly.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
cluster_exists || { ok "no cluster - nothing to clean"; exit 0; }

step "Delete namespace $LAB_NAMESPACE" "deletes the PVCs; dynamically provisioned PVs (reclaimPolicy Delete) go with them"
delete_ns "$LAB_NAMESPACE"

step "Delete cluster-scoped leftovers" "static-pv has reclaimPolicy Retain, so Kubernetes deliberately keeps it"
k delete pv static-pv --ignore-not-found >/dev/null && ok "pv static-pv removed"
k delete storageclass fast-ssd --ignore-not-found >/dev/null && ok "storageclass fast-ssd removed (if you created it)"

step "Remove the hostPath data from the nodes" "Retain means the data stays on disk until an admin removes it"
for node in $(kind get nodes --name "$CLUSTER_NAME"); do
  docker exec "$node" rm -rf /tmp/lab-static-pv
done
ok "cleanup complete"
