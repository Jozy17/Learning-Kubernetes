#!/usr/bin/env bash
# Lab t1-01 setup: prepares the namespace, base image and a local registry.
# You will build, run, push and deploy the image yourself (see README.md).
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"

require_cluster

step "Create namespace $LAB_NAMESPACE" \
     "namespaces keep each lab's objects separate, so cleanup is a single delete"
ensure_ns "$LAB_NAMESPACE"

step "Pull the base image $IMG_BUSYBOX" "your Dockerfile builds on top of it (FROM busybox)"
docker image inspect "$IMG_BUSYBOX" >/dev/null 2>&1 || docker pull -q "$IMG_BUSYBOX" >/dev/null
ok "$IMG_BUSYBOX present locally"

step "Start a private registry on localhost:$REGISTRY_PORT" \
     "a registry stores and serves images - like the image service in Prism, but for container images"
if [[ "$(docker inspect -f '{{.State.Running}}' "$REGISTRY_NAME" 2>/dev/null)" == "true" ]]; then
  ok "registry $REGISTRY_NAME already running"
elif docker inspect "$REGISTRY_NAME" >/dev/null 2>&1; then
  docker start "$REGISTRY_NAME" >/dev/null; ok "registry $REGISTRY_NAME restarted"
else
  docker run -d --restart=unless-stopped --name "$REGISTRY_NAME" \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" "$IMG_REGISTRY" >/dev/null
  ok "registry $REGISTRY_NAME started"
fi

step "Create your work folder" "you type your Dockerfile here; it is git-ignored"
mkdir -p "$DIR/work"
ok "${DIR#"$REPO_ROOT"/}/work"
