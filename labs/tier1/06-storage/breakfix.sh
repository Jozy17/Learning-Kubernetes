#!/usr/bin/env bash
# Lab t1-06 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    step "Deploy 'db' with its PVC" "simulates a manifest copied from another cluster that has different storage classes"
    k -n "$NS" delete deployment db --ignore-not-found --wait=true >/dev/null
    k -n "$NS" delete pvc db-data --ignore-not-found --wait=true >/dev/null
    k apply -f "$DIR/breakfix/db.yaml" >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "We copied the db manifests from the old cluster. The db pod has been
Pending since. Get it running with persistent storage."

Start with: kubectl -n $NS get pods,pvc ; kubectl -n $NS describe pvc db-data
When done:  ./labctl breakfix t1-06 --check
MSG
    ;;
  check)
    check "PVC db-data is Bound" test "$(jp "$NS" pvc/db-data '{.status.phase}')" = Bound
    hint "does the StorageClass the PVC asks for exist? (kubectl get storageclass)"
    check "db pod is Running" \
      test "$(k -n "$NS" get pods -l app=db -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" = Running
    check "db wrote its marker file to the volume" \
      bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec deploy/db -- cat /var/lib/db/started | grep -q started"
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
