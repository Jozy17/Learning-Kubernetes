#!/usr/bin/env bash
# Lab t1-06 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

check "PVC data-pvc is Bound, 1Gi, StorageClass standard" \
  test "$(jp "$NS" pvc/data-pvc '{.status.phase}/{.spec.resources.requests.storage}/{.spec.storageClassName}')" = "Bound/1Gi/standard"
hint "Task 2 + 3: the PVC only binds once a pod uses it (WaitForFirstConsumer)"
check "Pod writer is gone (you deleted it)" bash -c "! kubectl --context $KUBE_CONTEXT -n $NS get pod writer"
hint "Task 4: kubectl -n $NS delete pod writer"
check "Pod reader is Running and mounts data-pvc" \
  test "$(jp "$NS" pod/reader '{.status.phase}/{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}')" = "Running/data-pvc"
check "reader sees /data/proof.txt written by the writer pod" \
  bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec reader -- cat /data/proof.txt | grep -q 'written by writer'"
hint "the data must have been written by 'writer', then read by a *different* pod"
check "PV static-pv exists with reclaimPolicy Retain" \
  test "$(k get pv static-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)" = Retain
hint "Task 5"
check "static-pv is Bound to $NS/static-pvc" \
  test "$(k get pv static-pv -o jsonpath='{.status.phase}/{.spec.claimRef.namespace}/{.spec.claimRef.name}' 2>/dev/null)" = "Bound/$NS/static-pvc"
hint "static-pvc must use storageClassName: manual and ask for <= the PV's capacity"

verify_summary
