#!/usr/bin/env bash
# Lab t1-09 break/fix. Usage: breakfix.sh inject|check
# NOTE: this one changes your kubeconfig (~/.kube/config) - only the lab context.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
ctx_ns() { kubectl config view -o jsonpath="{.contexts[?(@.name==\"$KUBE_CONTEXT\")].context.namespace}"; }

case "${1:-}" in
  inject)
    step "Change the default namespace of context $KUBE_CONTEXT" \
         "simulates a colleague's 'helpful' one-liner with a typo - it happens on real teams all the time"
    kubectl config set-context "$KUBE_CONTEXT" --namespace=lab-kubect1 >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "After pairing with a colleague, 'kubectl get pods' and 'kubectl get deploy'
show 'No resources found', and a 'kubectl create deployment' failed with 'namespaces not found'.
The cluster looks empty! Nothing was deleted... right?"

Investigate WITHOUT typing -n or -A at first: what does kubectl think "here" is?
When done: ./labctl breakfix t1-09 --check
MSG
    ;;
  check)
    ns="$(ctx_ns)"
    check "Context $KUBE_CONTEXT's default namespace exists (or is unset)" \
      bash -c "[[ -z '$ns' ]] || kubectl --context $KUBE_CONTEXT get namespace '$ns'"
    hint "kubectl config get-contexts shows a NAMESPACE column"
    check "The estate is still there (4 Deployments in $LAB_NAMESPACE)" \
      test "$(k -n "$LAB_NAMESPACE" get deploy -o name | grep -cv '^deployment.apps/report$')" = 4
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
