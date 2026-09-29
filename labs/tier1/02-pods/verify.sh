#!/usr/bin/env bash
# Lab t1-02 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

check "Pod web is Running"                test "$(jp "$NS" pod/web '{.status.phase}')" = Running
hint "Task 1: kubectl -n $NS run web --image=$IMG_NGINX_OLD --labels=app=web,tier=frontend"
check "Pod web has labels app=web and tier=frontend" \
  test "$(jp "$NS" pod/web '{.metadata.labels.app}/{.metadata.labels.tier}')" = "web/frontend"
hint "kubectl -n $NS label pod web tier=frontend"
check "Pod web runs image $IMG_NGINX_OLD" test "$(jp "$NS" pod/web '{.spec.containers[0].image}')" = "$IMG_NGINX_OLD"

check "Pod shared-demo has 2 containers" \
  test "$(jp "$NS" pod/shared-demo '{.spec.containers[*].name}' | wc -w)" = 2
hint "Task 4: write work/shared-demo.yaml with a 'web' and a 'writer' container"
check "Both shared-demo containers are ready" \
  test "$(jp "$NS" pod/shared-demo '{.status.containerStatuses[*].ready}')" = "true true"
check "shared-demo uses an emptyDir volume" \
  bash -c "kubectl --context $KUBE_CONTEXT -n $NS get pod shared-demo -o jsonpath='{.spec.volumes[*].emptyDir}' | grep -q '{'"
check "Every shared-demo container sets CPU+memory requests and a memory limit" \
  bash -c "[[ \$(kubectl --context $KUBE_CONTEXT -n $NS get pod shared-demo -o jsonpath='{range .spec.containers[*]}{.resources.requests.cpu},{.resources.requests.memory},{.resources.limits.memory};{end}') =~ ^([^,;]+,[^,;]+,[^,;]+;){2}$ ]]"
hint "Task 5: add resources.requests (cpu, memory) and resources.limits.memory to BOTH containers"
check "nginx in shared-demo serves the file written by the writer container" \
  bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec shared-demo -c web -- wget -qO- http://localhost/ | grep -q 'hello from the writer'"
hint "writer must write /data/index.html; web must mount the same volume at /usr/share/nginx/html"

verify_summary
