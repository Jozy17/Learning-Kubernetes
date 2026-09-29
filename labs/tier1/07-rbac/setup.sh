#!/usr/bin/env bash
# Lab t1-07 setup: two namespaces and some objects to protect.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespaces $LAB_NAMESPACE and $OTHER_NAMESPACE" \
     "a second namespace lets you prove that permissions stop at the namespace boundary"
ensure_ns "$LAB_NAMESPACE"
ensure_ns "$OTHER_NAMESPACE"

step "Preload images" "for the sample Deployment"
load_images "$IMG_NGINX_OLD"

step "Create a Deployment, a Secret and a ConfigMap to protect" \
     "RBAC is easier to understand when there is something worth protecting"
k apply -f "$DIR/manifests/targets.yaml" >/dev/null
ok "targets created"
mkdir -p "$DIR/work"
