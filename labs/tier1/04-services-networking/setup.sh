#!/usr/bin/env bash
# Lab t1-04 setup: a backend Deployment + a client pod. You build the networking yourself.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespace $LAB_NAMESPACE" "an isolated area for this lab's objects"
ensure_ns "$LAB_NAMESPACE"

step "Preload images" "nginx for the backend, curl for the client"
load_images "$IMG_NGINX_OLD" "$IMG_CURL" "$IMG_BUSYBOX"

step "Deploy backend 'web' (3 replicas) and client pod 'toolbox'" \
     "networking is easier to learn when something is already running to connect to"
k apply -f "$DIR/manifests/backend.yaml" >/dev/null
k -n "$LAB_NAMESPACE" rollout status deployment/web --timeout=120s >/dev/null
k -n "$LAB_NAMESPACE" wait --for=condition=Ready pod/toolbox --timeout=120s >/dev/null
ok "web and toolbox are ready"
mkdir -p "$DIR/work"
