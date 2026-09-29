#!/usr/bin/env bash
# Lab t1-05 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    step "Deploy pod worker" "simulates an app deployed before its configuration was created"
    k -n "$NS" delete pod worker --ignore-not-found --wait=true >/dev/null
    k -n "$NS" delete configmap worker-settings --ignore-not-found >/dev/null
    k apply -f "$DIR/breakfix/worker.yaml" >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "Pod worker in $NS has been stuck for ages and never starts. Don't
delete or edit the pod. Fix whatever it's waiting for. It should log at level 'info'."

Start with: kubectl -n $NS get pod worker ; kubectl -n $NS describe pod worker
When done:  ./labctl breakfix t1-05 --check
MSG
    ;;
  check)
    check "Pod worker is Running" test "$(jp "$NS" pod/worker '{.status.phase}')" = Running
    hint "describe: the event mentions a missing ConfigMap - create it, and the kubelet retries on its own"
    check "worker logs 'log level is info'" bash -c "kubectl --context $KUBE_CONTEXT -n $NS logs worker | grep -q 'log level is info'"
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
