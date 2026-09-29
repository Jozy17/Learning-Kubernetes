#!/usr/bin/env bash
# Lab t1-04 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    step "Deploy 'api' Deployment + Service" "simulates a Service that was written by hand and never tested"
    k -n "$NS" delete svc api --ignore-not-found >/dev/null
    k apply -f "$DIR/breakfix/api.yaml" >/dev/null
    # If you completed Task 6, default-deny would also block toolbox -> api.
    # We add a narrow allow so the bug you chase is the Service, not the policy.
    k apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-toolbox-to-api, namespace: $NS}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {role: toolbox}}}]
YAML
    k -n "$NS" rollout status deployment/api --timeout=120s >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "From toolbox, 'curl http://api' fails. The api pods are Running and
healthy. Fix the Service; don't change the Deployment."

Try it:     kubectl -n $NS exec toolbox -- curl -s -m 5 http://api
Start with: kubectl -n $NS get svc api -o wide ; kubectl -n $NS get endpointslices
When done:  ./labctl breakfix t1-04 --check
MSG
    ;;
  check)
    check "Service api has ready endpoints" \
      test -n "$(k -n "$NS" get endpointslices -l kubernetes.io/service-name=api -o jsonpath='{.items[*].endpoints[*].addresses[0]}')"
    hint "compare the Service selector with the pod labels (kubectl get pods --show-labels)"
    check "toolbox gets 'api ok' from http://api" \
      bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec toolbox -- curl -s -m 5 http://api | grep -q 'api ok'"
    hint "endpoints exist but no answer? which port does nginx listen on vs the Service targetPort?"
    check "Deployment api unchanged (selector app=api)" \
      test "$(jp "$NS" deployment/api '{.spec.selector.matchLabels.app}')" = api
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
