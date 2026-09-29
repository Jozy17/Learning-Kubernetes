#!/usr/bin/env bash
# Lab t1-01 verify: checks the state your commands produced (not which commands you typed).
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

img_user() { docker image inspect hello-web:1.0 --format '{{.Config.User}}' 2>/dev/null; }

check "Image hello-web:1.0 exists locally"             docker image inspect hello-web:1.0
hint "Task 2: docker build -t hello-web:1.0 ."
check "Image runs as a non-root user (USER in Dockerfile)" \
  bash -c "u=\$(docker image inspect hello-web:1.0 --format '{{.Config.User}}'); [[ -n \$u && \$u != root && \$u != 0 && \$u != 0:0 ]]"
hint "Task 2: add 'USER 65534' to the Dockerfile and rebuild"
check "Registry localhost:$REGISTRY_PORT has hello-web:1.0" \
  bash -c "curl -fsS http://localhost:$REGISTRY_PORT/v2/hello-web/tags/list | grep -q '\"1.0\"'"
hint "Task 4: docker tag + docker push localhost:$REGISTRY_PORT/hello-web:1.0"
check "Pod hello-web in $NS is Running image hello-web:1.0" \
  bash -c "[[ \$(kubectl --context $KUBE_CONTEXT -n $NS get pod hello-web -o jsonpath='{.status.phase}/{.spec.containers[0].image}') == 'Running/hello-web:1.0' ]]"
hint "Task 5: kind load docker-image ..., then kubectl run hello-web ..."
check "hello-web serves your page on port 8080" \
  bash -c "kubectl --context $KUBE_CONTEXT -n $NS exec hello-web -- wget -qO- http://localhost:8080/ | grep -qi 'hello'"
hint "index.html should contain the word 'Hello'; httpd must listen on 8080"

verify_summary
