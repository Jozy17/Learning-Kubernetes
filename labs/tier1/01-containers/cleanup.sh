#!/usr/bin/env bash
# Lab t1-01 cleanup: removes everything the lab created. Safe to run repeatedly.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"

if cluster_exists; then
  step "Delete namespace $LAB_NAMESPACE" "deleting a namespace deletes every object inside it"
  delete_ns "$LAB_NAMESPACE"
  step "Remove hello-web images from the kind nodes" "images you 'kind load'-ed stay in each node's containerd until removed"
  for node in $(kind get nodes --name "$CLUSTER_NAME"); do
    for tag in 1.0 2.0; do
      docker exec "$node" crictl rmi "docker.io/library/hello-web:$tag" >/dev/null 2>&1 || true
    done
  done
  ok "node images removed"
fi

step "Remove local containers, registry and images" "keeps Docker tidy; images can always be rebuilt"
for c in hello-web "$REGISTRY_NAME"; do
  if docker inspect "$c" >/dev/null 2>&1; then docker rm -f "$c" >/dev/null; ok "removed container $c"; fi
done
for i in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '(^|/)hello-web:' || true); do
  docker rmi "$i" >/dev/null && ok "removed image $i"
done
ok "cleanup complete (your notes in ${DIR#"$REPO_ROOT"/}/work were kept)"
