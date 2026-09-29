#!/usr/bin/env bash
# Lab t1-03 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"
d() { jp "$NS" deployment/web "$1"; }

check "Deployment web exists"                         k -n "$NS" get deployment web
hint "Task 1: kubectl apply -f work/web-deployment.yaml"
check "web wants 3 replicas and has 3 ready"          test "$(d '{.spec.replicas}/{.status.readyReplicas}')" = "3/3"
hint "Task 4: scale back to 3 when you're done experimenting"
check "web runs $IMG_NGINX_NEW (rolling update done)" test "$(d '{.spec.template.spec.containers[0].image}')" = "$IMG_NGINX_NEW"
hint "Task 5: kubectl set image deployment/web nginx=$IMG_NGINX_NEW"
check "All web pods are updated (rollout complete)"   test "$(d '{.status.updatedReplicas}')" = 3
check "At least 2 ReplicaSets exist (rollout history)" \
  test "$(k -n "$NS" get rs -l app=web -o name | wc -l)" -ge 2
check "Rolling update never removes a ready pod (maxUnavailable: 0)" \
  test "$(d '{.spec.strategy.rollingUpdate.maxUnavailable}')" = 0
hint "Task 1: set spec.strategy.rollingUpdate.maxUnavailable: 0"
check "Container has a readinessProbe"                test -n "$(d '{.spec.template.spec.containers[0].readinessProbe}')"
hint "Task 1: add readinessProbe (httpGet path / port 80)"
check "change-cause annotation records why the last change happened" \
  test -n "$(d '{.metadata.annotations.kubernetes\.io/change-cause}')"
hint "Task 5: kubectl annotate deployment/web kubernetes.io/change-cause='...'"

verify_summary
