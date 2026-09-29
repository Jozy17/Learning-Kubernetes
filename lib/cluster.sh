#!/usr/bin/env bash
# Create / delete / inspect the shared kind lab cluster. Called by labctl.
set -o errexit -o nounset -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BASE_CONFIG="$REPO_ROOT/clusters/kind-k8slab.yaml"

# Some hosts need compatibility settings. We detect them instead of guessing:
#   1. cgroup v1 hosts: Kubernetes >= 1.35 refuses to start on cgroup v1 unless
#      the kubelet sets failCgroupV1=false. WSL2 on current Windows 11 normally
#      uses cgroup v2, so you probably will NOT need this.
#   2. Hosts where containers may not lower their OOM score (missing the
#      CAP_SYS_RESOURCE capability, e.g. some sandboxes). containerd's
#      restrict_oom_score_adj option (built for rootless mode) handles that.
# LABCTL_COMPAT=auto (default) | on | off
compat_patches() {
  local mode="${LABCTL_COMPAT:-auto}" cg v1=0 oom=0
  [[ "$mode" == off ]] && return 0
  cg="$(docker info --format '{{.CgroupVersion}}' 2>/dev/null || echo 2)"
  [[ "$cg" == 1 || "$mode" == on ]] && v1=1
  if [[ "$mode" == on ]] || ! docker run --rm --privileged --entrypoint sh "$KIND_NODE_IMAGE" \
        -c 'echo -999 > /proc/self/oom_score_adj' >/dev/null 2>&1; then
    oom=1
  fi
  if (( oom )); then
    warn "host cannot lower OOM scores; enabling containerd restrict_oom_score_adj" >&2
    cat <<'YAML'
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri"]
    restrict_oom_score_adj = true
YAML
  fi
  if (( v1 || oom )); then
    echo "kubeadmConfigPatches:"
    if (( v1 )); then
      warn "Docker reports cgroup v1; setting kubelet failCgroupV1=false" >&2
      printf '%s\n' "- |" "  kind: KubeletConfiguration" "  failCgroupV1: false"
    fi
    if (( oom )); then
      printf '%s\n' "- |" "  kind: KubeProxyConfiguration" "  oomScoreAdj: 0"
    fi
  fi
}

cmd_up() {
  command -v kind >/dev/null || die "kind not found. Run: ./labctl install-tools"
  command -v kubectl >/dev/null || die "kubectl not found. Run: ./labctl install-tools"
  docker info >/dev/null 2>&1 || die "Docker is not running (in WSL2: sudo systemctl start docker)"

  if cluster_exists; then
    ok "cluster '$CLUSTER_NAME' already exists (nothing to do)"
    return 0
  fi

  step "Pull the pinned node image" \
       "each kind 'node' is a container started from this image; it contains kubelet + containerd"
  docker image inspect "$KIND_NODE_IMAGE" >/dev/null 2>&1 || docker pull "$KIND_NODE_IMAGE"

  step "Create the kind cluster '$CLUSTER_NAME' (1 control-plane, 2 workers)" \
       "kubeadm bootstraps a real Kubernetes control plane inside the first container, then joins the workers"
  mkdir -p "$STATE_DIR"
  local cfg="$STATE_DIR/kind-config.generated.yaml"
  { sed "s/^name: .*/name: $CLUSTER_NAME/" "$BASE_CONFIG"; compat_patches; } > "$cfg"
  kind create cluster --config "$cfg" --image "$KIND_NODE_IMAGE" --wait 180s

  step "Wait for all nodes to be Ready" "Ready means kubelet is healthy and the pod network (kindnet) is up on that node"
  k wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
  k get nodes -o wide
  echo
  info "Your kubectl context is now '$KUBE_CONTEXT'. Check with: kubectl config current-context"
}

cmd_down() {
  if cluster_exists; then
    step "Delete kind cluster '$CLUSTER_NAME'" "removes the node containers and their data; your repo is untouched"
    kind delete cluster --name "$CLUSTER_NAME"
  else
    ok "cluster '$CLUSTER_NAME' does not exist (nothing to do)"
  fi
}

cmd_status() {
  if ! cluster_exists; then
    info "cluster '$CLUSTER_NAME' does not exist. Create it with: ./labctl cluster up"
    return 0
  fi
  k get nodes -o wide
  echo
  info "Lab namespaces:"
  k get namespaces -l app.kubernetes.io/managed-by=labctl 2>/dev/null || true
}

case "${1:-}" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  *) die "usage: cluster.sh up|down|status" ;;
esac
