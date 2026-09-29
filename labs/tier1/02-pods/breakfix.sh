#!/usr/bin/env bash
# Lab t1-02 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

case "${1:-}" in
  inject)
    step "Deploy pod api" "simulates a container whose start command points at a config file that doesn't exist"
    k delete pod api -n "$NS" --ignore-not-found --wait=true >/dev/null
    k apply -f "$DIR/breakfix/api.yaml" >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "Pod api in $NS keeps restarting. It should just run the stock nginx
config. Please make it stable." (manifest: labs/tier1/02-pods/breakfix/api.yaml)

Start with: kubectl -n $NS get pod api -w     (Ctrl+C to stop watching)
When done: ./labctl breakfix t1-02 --check
MSG
    ;;
  check)
    check "Pod api is Running and Ready" \
      test "$(jp "$NS" pod/api '{.status.phase}/{.status.containerStatuses[0].ready}')" = "Running/true"
    hint "kubectl logs api (or --previous) shows why the container dies"
    check "Pod api has not restarted" test "$(jp "$NS" pod/api '{.status.containerStatuses[0].restartCount}')" = 0
    hint "a pod's command can't be edited in place: delete it and re-create it from a fixed manifest"
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
