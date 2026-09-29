#!/usr/bin/env bash
# Lab t1-02 cleanup (idempotent)
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
cluster_exists || { ok "no cluster - nothing to clean"; exit 0; }
step "Delete namespace $LAB_NAMESPACE" "removes every pod and object this lab created"
delete_ns "$LAB_NAMESPACE"
ok "cleanup complete (your YAML in ${DIR#"$REPO_ROOT"/}/work was kept)"
