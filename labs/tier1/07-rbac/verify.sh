#!/usr/bin/env bash
# Lab t1-07 verify. `kubectl auth can-i` exits 0 for "yes" and 1 for "no",
# so each check is simply "can" or "cannot".
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"
can()    { local sa="$1" ns="$2"; shift 2; k auth can-i "$@" -n "$ns" --as="system:serviceaccount:$NS:$sa" >/dev/null 2>&1; }
cannot() { ! can "$@"; }

check "ServiceAccounts auditor, deployer, viewer exist" k -n "$NS" get sa auditor deployer viewer
hint "Tasks 2-4"
check "auditor CAN list pods in $NS"              can auditor "$NS" list pods
check "auditor CAN read pod logs in $NS"          can auditor "$NS" get pods --subresource=log
check "auditor CANNOT read secrets"               cannot auditor "$NS" get secrets
check "auditor CANNOT delete pods"                cannot auditor "$NS" delete pods
check "auditor CANNOT list pods in $OTHER_NAMESPACE" cannot auditor "$OTHER_NAMESPACE" list pods
hint "use a Role + RoleBinding (namespaced), not a ClusterRoleBinding"
check "deployer CAN create and patch deployments in $NS" \
  bash -c "kubectl --context $KUBE_CONTEXT auth can-i create deployments.apps -n $NS --as=system:serviceaccount:$NS:deployer && kubectl --context $KUBE_CONTEXT auth can-i patch deployments.apps -n $NS --as=system:serviceaccount:$NS:deployer"
check "deployer CANNOT create deployments in default" cannot deployer default create deployments.apps
check "deployer CANNOT read secrets"             cannot deployer "$NS" get secrets
check "viewer CAN list deployments in $NS (built-in 'view' role)" can viewer "$NS" list deployments.apps
check "viewer CANNOT read secrets ('view' excludes them)" cannot viewer "$NS" get secrets
check "No lab ServiceAccount is bound to cluster-admin" \
  bash -c "! kubectl --context $KUBE_CONTEXT get clusterrolebindings -o jsonpath='{range .items[?(@.roleRef.name==\"cluster-admin\")]}{.subjects[*].namespace}{\"\\n\"}{end}' | grep -q '^$NS'"

verify_summary
