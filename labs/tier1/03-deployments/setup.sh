#!/usr/bin/env bash
# Lab t1-03 setup: namespace + both nginx versions (for the rolling update).
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespace $LAB_NAMESPACE" "an isolated area for this lab's objects"
ensure_ns "$LAB_NAMESPACE"

step "Preload nginx old + new versions" "you'll roll the Deployment from one version to the other"
load_images "$IMG_NGINX_OLD" "$IMG_NGINX_NEW"

step "Create your work folder" "you'll write the Deployment YAML here (git-ignored)"
mkdir -p "$DIR/work"; ok "${DIR#"$REPO_ROOT"/}/work"
