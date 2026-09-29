#!/usr/bin/env bash
# Lab t1-05 setup: namespace + image. You create the quota, config and secrets yourself.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespace $LAB_NAMESPACE" "you'll put a quota on it - a namespace is also a unit of resource governance"
ensure_ns "$LAB_NAMESPACE"

step "Preload images" "busybox is a tiny image with a shell, handy for inspecting config"
load_images "$IMG_BUSYBOX"

step "Create your work folder" "for the app.properties file and pod YAML (git-ignored)"
mkdir -p "$DIR/work"; ok "${DIR#"$REPO_ROOT"/}/work"
