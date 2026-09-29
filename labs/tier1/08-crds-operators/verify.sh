#!/usr/bin/env bash
# Lab t1-08 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"
crd() { k get crd "$CRD_NAME" -o jsonpath="$1" 2>/dev/null; }

check "CRD $CRD_NAME is Established" \
  test "$(crd '{.status.conditions[?(@.type=="Established")].status}')" = True
hint "Task 2: kubectl apply -f work/vmrequest-crd.yaml"
check "CRD is namespaced, kind VMRequest, short name vmr" \
  test "$(crd '{.spec.scope}/{.spec.names.kind}/{.spec.names.shortNames[0]}')" = "Namespaced/VMRequest/vmr"
check "CRD enables the status subresource" test -n "$(crd '{.spec.versions[0].subresources.status}')"
check "CRD has printer columns (CPU/Phase shown by kubectl get)" \
  test -n "$(crd '{.spec.versions[0].additionalPrinterColumns[0].name}')"
check "Schema rejects cpu: 64 (maximum is 16)" bash -c "! kubectl --context $KUBE_CONTEXT apply --dry-run=server -f - >/dev/null 2>&1 <<YAML
apiVersion: lab.example.com/v1alpha1
kind: VMRequest
metadata: {name: too-big, namespace: $NS}
spec: {cpu: 64, memoryGi: 4, image: ubuntu-24.04}
YAML"
hint "Task 2: spec.cpu needs minimum: 1, maximum: 16"
check "Schema rejects a VMRequest without an image" bash -c "! kubectl --context $KUBE_CONTEXT apply --dry-run=server -f - >/dev/null 2>&1 <<YAML
apiVersion: lab.example.com/v1alpha1
kind: VMRequest
metadata: {name: no-image, namespace: $NS}
spec: {cpu: 2, memoryGi: 4}
YAML"
hint "Task 2: spec.required must include image"
check "VMRequest web-01 exists with 2 vCPU" test "$(jp "$NS" vmrequest/web-01 '{.spec.cpu}')" = 2
hint "Task 3"
check "web-01 status.phase is Provisioned (the controller ran)" test "$(jp "$NS" vmrequest/web-01 '{.status.phase}')" = Provisioned
hint "Task 5: run ./controller.sh in a second terminal"
check "ConfigMap web-01-vm is owned by VMRequest web-01" \
  test "$(jp "$NS" configmap/web-01-vm '{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" = "VMRequest/web-01"
check "web-01-vm reflects the updated memory (memoryGi 8)" test "$(jp "$NS" configmap/web-01-vm '{.data.memoryGi}')" = 8
hint "Task 6: edit web-01 to memoryGi: 8 while the controller runs"
check "db-01 was deleted and garbage collection removed db-01-vm" \
  bash -c "! kubectl --context $KUBE_CONTEXT -n $NS get vmrequest db-01 && ! kubectl --context $KUBE_CONTEXT -n $NS get configmap db-01-vm"
hint "Task 7"

verify_summary
