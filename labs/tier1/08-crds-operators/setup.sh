#!/usr/bin/env bash
# Lab t1-08 setup: just a namespace. You write the CRD yourself - that's the lab.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespace $LAB_NAMESPACE" "VMRequests will be namespaced objects, like KubeVirt VirtualMachines"
ensure_ns "$LAB_NAMESPACE"

step "Create your work folder" "for the CRD and the custom resources you write (git-ignored)"
mkdir -p "$DIR/work"; ok "${DIR#"$REPO_ROOT"/}/work"
