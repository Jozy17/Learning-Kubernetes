#!/usr/bin/env bash
# Lab t1-08 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    k get crd "$CRD_NAME" >/dev/null 2>&1 || die "finish the lab tasks first (the CRD must exist)"
    step "Create VMRequest legacy-01 with a finalizer, then delete it" \
         "simulates an object whose cleanup controller was uninstalled - a common cause of stuck deletions"
    k apply -f - >/dev/null <<YAML
apiVersion: lab.example.com/v1alpha1
kind: VMRequest
metadata:
  name: legacy-01
  namespace: $NS
  finalizers: ["lab.example.com/disk-cleanup"]
spec: {cpu: 1, memoryGi: 1, image: centos-7}
YAML
    k -n "$NS" delete vmrequest legacy-01 --wait=false >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "VMRequest legacy-01 in $NS was deleted an hour ago but it's still there.
'kubectl delete' just hangs. The disk-cleanup controller that used to handle these was
decommissioned last month, and there are no disks left to clean. Make it go away. Don't
touch the CRD or the other VMRequests."

Start with: kubectl -n $NS get vmr legacy-01 -o yaml   (look at metadata)
When done:  ./labctl breakfix t1-08 --check
MSG
    ;;
  check)
    check "legacy-01 is gone" bash -c "! kubectl --context $KUBE_CONTEXT -n $NS get vmrequest legacy-01"
    hint "metadata.deletionTimestamp is set, but metadata.finalizers is not empty"
    check "The CRD is still installed" k get crd "$CRD_NAME"
    check "web-01 is untouched" k -n "$NS" get vmrequest web-01
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
