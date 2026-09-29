#!/usr/bin/env bash
# Lab t1-03 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    step "Deploy the 'api' Deployment" "simulates a health check pointed at the wrong port - pods run but never become Ready"
    k delete deployment api -n "$NS" --ignore-not-found --wait=true >/dev/null
    k apply -f "$DIR/breakfix/api.yaml" >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "The api Deployment in $NS shows 0/3 ready. The pods say Running, and the
logs look fine. The load balancer won't send traffic to them. What's wrong?"

Start with: kubectl -n $NS get deploy,pods -l app=api
When done: ./labctl breakfix t1-03 --check
MSG
    ;;
  check)
    check "api has 3/3 ready replicas" test "$(jp "$NS" deployment/api '{.status.readyReplicas}')" = 3
    hint "describe one of the api pods and read the Events (look for 'Readiness probe failed')"
    check "api still has a readinessProbe (don't just delete the health check!)" \
      test -n "$(jp "$NS" deployment/api '{.spec.template.spec.containers[0].readinessProbe}')"
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
