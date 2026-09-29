#!/usr/bin/env bash
# Lab t1-06 setup: namespace + image. You create all storage objects yourself.
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster

step "Create namespace $LAB_NAMESPACE" "PVCs are namespaced; PVs and StorageClasses are cluster-wide"
ensure_ns "$LAB_NAMESPACE"

step "Preload images" "busybox writes and reads files on your volumes"
load_images "$IMG_BUSYBOX"

step "Show the StorageClass kind ships with" "this is the 'storage container' your PVCs will be carved from"
k get storageclass

mkdir -p "$DIR/work"
