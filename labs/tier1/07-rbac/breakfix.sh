#!/usr/bin/env bash
# Lab t1-07 break/fix. Usage: breakfix.sh inject|check
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"
AS="system:serviceaccount:$NS:ci-bot"
can() { k auth can-i "$@" -n "$NS" --as="$AS" >/dev/null 2>&1; }

case "${1:-}" in
  inject)
    step "Create ServiceAccount ci-bot with its Role and RoleBinding" "simulates RBAC written from memory and never tested"
    k -n "$NS" delete rolebinding ci-bot-binding --ignore-not-found >/dev/null
    k apply -f "$DIR/breakfix/ci-bot.yaml" >/dev/null
    cat <<MSG

${C_BOLD}Ticket:${C_RESET} "Our CI job runs as ServiceAccount ci-bot in $NS and does
  kubectl -n $NS set image deployment/app nginx=<new image>
It fails with 'Forbidden'. Give it EXACTLY what it needs - security will review this."

Reproduce: kubectl -n $NS set image deployment/app nginx=nginx:1.30-alpine --as=$AS --dry-run=server
When done: ./labctl breakfix t1-07 --check
MSG
    ;;
  check)
    check "ci-bot CAN get deployments in $NS" can get deployments.apps
    hint "who is the RoleBinding's subject? check the subject's namespace"
    check "ci-bot CAN patch deployments in $NS (set image = PATCH)" can patch deployments.apps
    hint "which verb does 'set image' use? add it to the Role"
    check "ci-bot CANNOT delete deployments (least privilege)" bash -c "! kubectl --context $KUBE_CONTEXT auth can-i delete deployments.apps -n $NS --as=$AS"
    check "ci-bot CANNOT read secrets (least privilege)"      bash -c "! kubectl --context $KUBE_CONTEXT auth can-i get secrets -n $NS --as=$AS"
    check "ci-bot has no rights in other namespaces"          bash -c "! kubectl --context $KUBE_CONTEXT auth can-i patch deployments.apps -n default --as=$AS"
    check "server-side dry-run of the CI command succeeds" \
      k -n "$NS" set image deployment/app nginx="$IMG_NGINX_NEW" --as="$AS" --dry-run=server
    verify_summary
    ;;
  *) die "usage: breakfix.sh inject|check" ;;
esac
