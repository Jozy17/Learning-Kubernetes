#!/usr/bin/env bash
# Lab t1-09 cleanup (idempotent)
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"

step "Reset the default namespace of context $KUBE_CONTEXT" "undo the break/fix (and any set-context you did in the tasks)"
kubectl config unset "contexts.$KUBE_CONTEXT.namespace" >/dev/null 2>&1 || true
ok "context namespace unset (kubectl uses 'default')"

cluster_exists || { ok "no cluster - nothing more to clean"; exit 0; }
step "Delete namespace $LAB_NAMESPACE" "removes the whole estate"
delete_ns "$LAB_NAMESPACE"
ok "cleanup complete"
