#!/usr/bin/env bash
# Lab t1-01 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    step "Deploy pod hello-v2" "simulates a release that references an image nobody has built/published yet"
    k apply -f "$DIR/breakfix/hello-v2.yaml" >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "The v2 release of hello-web never came up. Pod hello-v2 in $NS isn't
serving. Please get it running. It should serve a page containing 'v2'."

Start with: kubectl -n $NS get pods   and   kubectl -n $NS describe pod hello-v2
When done: ./labctl breakfix t1-01 --check
MSG
    ;;
  check)
    check "Pod hello-v2 is Running" \
      test "$(jp "$NS" pod/hello-v2 '{.status.phase}')" = Running
    hint "describe the pod: what do the Events say about the image?"
    check "hello-v2 serves a page containing 'v2'" \
      bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec hello-v2 -- wget -qO- http://localhost:8080/ | grep -q v2"
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
