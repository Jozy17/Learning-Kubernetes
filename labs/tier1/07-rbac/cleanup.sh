#!/usr/bin/env bash
# Lab t1-07 cleanup (idempotent). Roles/RoleBindings live in the namespaces,
# so deleting both namespaces removes them. We also sweep ClusterRoleBindings
# that point at our ServiceAccounts, in case you experimented with those.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
cluster_exists || { ok "no cluster - nothing to clean"; exit 0; }

step "Delete ClusterRoleBindings that reference lab ServiceAccounts" "cluster-scoped objects survive namespace deletion"
for crb in $(k get clusterrolebindings -o jsonpath="{range .items[*]}{.metadata.name}{' '}{.subjects[*].namespace}{'\n'}{end}" \
             | awk -v ns="$LAB_NAMESPACE" '$0 ~ ns {print $1}'); do
  k delete clusterrolebinding "$crb" >/dev/null && ok "deleted clusterrolebinding $crb"
done

step "Delete namespaces" "removes ServiceAccounts, Roles, RoleBindings and the sample objects"
delete_ns "$LAB_NAMESPACE"
delete_ns "$OTHER_NAMESPACE"
ok "cleanup complete"
