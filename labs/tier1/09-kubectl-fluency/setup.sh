#!/usr/bin/env bash
# Lab t1-09 setup: builds a small estate of workloads for you to search and change.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

step "Create namespace $NS" "the estate lives here"
ensure_ns "$NS"

step "Preload images" "nginx (two versions) and busybox"
load_images "$IMG_NGINX_OLD" "$IMG_NGINX_NEW" "$IMG_BUSYBOX"

step "Deploy the estate: 4 Deployments and 2 batch pods (one failed)" \
     "fluency comes from finding things in a cluster you didn't build"
# Batch pods are immutable and run once; recreate them only if missing.
k apply -f "$DIR/manifests/estate.yaml" >/dev/null 2>&1 || {
  k -n "$NS" delete pod -l tier=batch --ignore-not-found >/dev/null
  k apply -f "$DIR/manifests/estate.yaml" >/dev/null
}
for d in frontend backend cache reporting; do k -n "$NS" rollout status "deployment/$d" --timeout=120s >/dev/null; done
ok "estate is up"
mkdir -p "$DIR/work"
