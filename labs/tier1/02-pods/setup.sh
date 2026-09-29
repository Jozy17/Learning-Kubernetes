#!/usr/bin/env bash
# Lab t1-02 setup: namespace + images only. You create the pods yourself.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespace $LAB_NAMESPACE" "an isolated area for this lab's objects"
ensure_ns "$LAB_NAMESPACE"

step "Preload images" "so pods start instantly and don't depend on Docker Hub"
load_images "$IMG_NGINX_OLD" "$IMG_BUSYBOX"

step "Create your work folder" "you'll write pod YAML here (git-ignored)"
mkdir -p "$DIR/work"; ok "${DIR#"$REPO_ROOT"/}/work"
