#!/usr/bin/env bash
# Lab t1-04 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

check "Service web is type ClusterIP on port 80" test "$(jp "$NS" svc/web '{.spec.type}/{.spec.ports[0].port}')" = "ClusterIP/80"
hint "Task 1: kubectl -n $NS expose deployment web --port=80"
check "Service web selects app=web"               test "$(jp "$NS" svc/web '{.spec.selector.app}')" = web
check "Service web has 3 ready endpoints" \
  test "$(k -n "$NS" get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}')" = xxx
check "toolbox reaches web via its DNS name" \
  bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec toolbox -- curl -s -m 5 http://web.$NS.svc.cluster.local | grep -q 'served by'"
check "Service web-nodeport is NodePort 30080 -> app=web" \
  test "$(jp "$NS" svc/web-nodeport '{.spec.type}/{.spec.ports[0].nodePort}/{.spec.selector.app}')" = "NodePort/30080/web"
hint "Task 4: create it from YAML with nodePort: 30080"
check "http://localhost:30080 on your machine answers" bash -c "curl -s -m 5 http://localhost:30080 | grep -q 'served by'"
hint "kind maps localhost:30080 to the control-plane node (see clusters/kind-k8slab.yaml)"
check "NetworkPolicy default-deny-ingress selects all pods, Ingress only" \
  test "$(jp "$NS" networkpolicy/default-deny-ingress '{.spec.podSelector}/{.spec.policyTypes[*]}')" = "{}/Ingress"
hint "Task 6"
check "NetworkPolicy allow-toolbox-to-web: app=web from role=toolbox on TCP 80" \
  test "$(jp "$NS" networkpolicy/allow-toolbox-to-web '{.spec.podSelector.matchLabels.app}/{.spec.ingress[0].from[0].podSelector.matchLabels.role}/{.spec.ingress[0].ports[0].port}')" = "web/toolbox/80"
hint "Task 6"

# Enforcement depends on the CNI and the kernel, so we report it but don't grade it.
if k -n "$NS" get networkpolicy default-deny-ingress >/dev/null 2>&1; then
  k -n "$NS" delete pod np-probe --ignore-not-found --wait=true >/dev/null 2>&1
  if k -n "$NS" run np-probe --image="$IMG_BUSYBOX" --restart=Never --rm -i --quiet --command -- \
       wget -qO- -T 3 http://web >/dev/null 2>&1; then
    info "info: an unlabelled pod could still reach web -> policies are NOT enforced on this cluster (see README 'Enforcement')"
  else
    info "info: an unlabelled pod was blocked -> your NetworkPolicies are enforced"
  fi
fi
verify_summary
