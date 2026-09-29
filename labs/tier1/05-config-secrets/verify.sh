#!/usr/bin/env bash
# Lab t1-05 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"
ex() { k -n "$NS" exec app -- "$@"; }

check "ResourceQuota compute-quota limits pods and requests.cpu" \
  bash -c "[[ -n \$(kubectl --context $KUBE_CONTEXT -n $NS get resourcequota compute-quota -o jsonpath='{.spec.hard.pods}') && -n \$(kubectl --context $KUBE_CONTEXT -n $NS get resourcequota compute-quota -o jsonpath='{.spec.hard.requests\.cpu}') ]]"
hint "Task 1"
check "LimitRange default-resources sets default requests for containers" \
  test -n "$(jp "$NS" limitrange/default-resources '{.spec.limits[0].defaultRequest.cpu}')"
hint "Task 1"
check "ConfigMap app-config has APP_MODE=training" test "$(jp "$NS" configmap/app-config '{.data.APP_MODE}')" = training
hint "Task 2: kubectl create configmap app-config --from-literal=APP_MODE=training ..."
check "ConfigMap app-config has the key app.properties" \
  test -n "$(jp "$NS" configmap/app-config '{.data.app\.properties}')"
hint "Task 2: --from-file=work/app.properties"
check "Secret db-credentials (Opaque) has username + password" \
  test "$(jp "$NS" secret/db-credentials '{.type}/{.data.username}/{.data.password}' | awk -F/ '$1=="Opaque" && $2!="" && $3!=""{print "ok"}')" = ok
hint "Task 3"
check "Pod app is Running"                        test "$(jp "$NS" pod/app '{.status.phase}')" = Running
hint "Task 4: kubectl apply -f work/app-pod.yaml"
check "app sees env APP_MODE=training from the ConfigMap" bash -c "[[ \$(kubectl --context $KUBE_CONTEXT -n $NS exec app -- printenv APP_MODE) == training ]]"
check "app has the ConfigMap file at /etc/app/app.properties" ex test -f /etc/app/app.properties
check "app has the Secret mounted read-only at /etc/db (password file)" ex test -f /etc/db/password
check "Secret is NOT exposed as an environment variable (file mount only)" \
  bash -c "! kubectl --context $KUBE_CONTEXT -n $NS get pod app -o yaml | grep -q secretKeyRef"
hint "Task 4 security note: mount secrets as files instead of env vars"
check "Pod app received default requests from the LimitRange" \
  test -n "$(jp "$NS" pod/app '{.spec.containers[0].resources.requests.cpu}')"

verify_summary
