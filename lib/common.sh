#!/usr/bin/env bash
# Shared helpers for labctl and every lab script.
# Lab scripts `source` this file; it is not meant to be run directly.
#
# Design rules (so you can read any lab script and know what to expect):
#   * Every step prints WHAT it does and WHY.
#   * Every kubectl call goes through `k`, which pins --context to the lab
#     cluster. Why: later you will have work clusters in ~/.kube/config too,
#     and a lab script must never be able to touch them by accident.
#   * Scripts are idempotent: running them twice gives the same result.

# shellcheck disable=SC2034  # variables here are used by the scripts that source us

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$REPO_ROOT/versions.env"

CLUSTER_NAME="${LABCTL_CLUSTER_NAME:-k8slab}"
KUBE_CONTEXT="kind-${CLUSTER_NAME}"
STATE_DIR="$REPO_ROOT/.labctl"

# Put tools installed by `labctl install-tools` on PATH for scripts too.
export PATH="$HOME/.local/bin:$PATH"

# ---------- output ----------
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

info()  { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}ok${C_RESET}  $*"; }
warn()  { printf '%s\n' "${C_YELLOW}warn${C_RESET} $*" >&2; }
die()   { printf '%s\n' "${C_RED}error${C_RESET} $*" >&2; exit 1; }

# step "what" "why" -- announce a script step and the reason for it.
step() {
  printf '\n%s\n' "${C_BOLD}▶ $1${C_RESET}"
  [[ -n "${2:-}" ]] && printf '%s\n' "  ${C_DIM}why: $2${C_RESET}"
  return 0
}

# ---------- kubectl / cluster ----------
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

cluster_exists() {
  command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"
}

require_cluster() {
  cluster_exists || die "lab cluster '$CLUSTER_NAME' not found. Run: ./labctl cluster up"
  k get --raw=/readyz >/dev/null 2>&1 || die "cluster '$CLUSTER_NAME' exists but the API is not answering. Try: ./labctl cluster status"
}

# ensure_ns NAME -- create a namespace if missing, labelled so we can find lab namespaces later.
ensure_ns() {
  k create namespace "$1" --dry-run=client -o yaml \
    | k label --local -f - app.kubernetes.io/managed-by=labctl -o yaml \
    | k apply -f - >/dev/null
  ok "namespace $1"
}

# delete_ns NAME -- delete a namespace and wait (idempotent).
delete_ns() {
  if k get namespace "$1" >/dev/null 2>&1; then
    k delete namespace "$1" --wait=true --timeout=120s >/dev/null
    ok "deleted namespace $1"
  else
    ok "namespace $1 already gone"
  fi
}

# load_images IMAGE... -- pull on the host, then copy into every kind node.
# Why: pods then start without reaching Docker Hub (faster, no rate limits,
# works behind restrictive proxies).
# How: `docker save --platform` exports just our CPU architecture. (Plain
# `kind load docker-image` can fail with Docker 29's multi-platform image
# store: "content digest ... not found".)
load_images() {
  local img node missing arch tmp
  arch="$(docker version --format '{{.Server.Arch}}')"
  for img in "$@"; do
    missing=0
    for node in $(kind get nodes --name "$CLUSTER_NAME"); do
      docker exec "$node" crictl inspecti "$img" >/dev/null 2>&1 || missing=1
    done
    if (( missing )); then
      if ! docker image inspect "$img" >/dev/null 2>&1; then
        docker pull -q --platform "linux/$arch" "$img" >/dev/null || die "could not pull $img"
      fi
      tmp="$(mktemp)"
      docker save --platform "linux/$arch" "$img" -o "$tmp" \
        && kind load image-archive "$tmp" --name "$CLUSTER_NAME" >/dev/null 2>&1 \
        || { rm -f "$tmp"; die "could not load $img into the cluster"; }
      rm -f "$tmp"
    fi
    ok "image $img available on all nodes"
  done
}

# wait_for "description" TIMEOUT_SECONDS command... -- poll until command succeeds.
wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    (( waited >= timeout )) && { warn "timed out waiting for: $desc"; return 1; }
    sleep 2; waited=$((waited + 2))
  done
}

# ---------- verify helpers ----------
# Usage in verify.sh:
#   check "Deployment web has 3 ready replicas" \
#     test "$(k -n ns get deploy web -o jsonpath='{.status.readyReplicas}')" = 3
#   verify_summary
CHECKS_PASSED=0
CHECKS_FAILED=0
LAST_CHECK_OK=1

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  %s %s\n' "${C_GREEN}✔${C_RESET}" "$desc"
    CHECKS_PASSED=$((CHECKS_PASSED + 1)); LAST_CHECK_OK=1
  else
    printf '  %s %s\n' "${C_RED}✘${C_RESET}" "$desc"
    CHECKS_FAILED=$((CHECKS_FAILED + 1)); LAST_CHECK_OK=0
  fi
  return 0
}

# hint "text" -- print a hint only if the check right before it failed.
hint() {
  (( LAST_CHECK_OK )) || printf '      %s\n' "${C_DIM}hint: $*${C_RESET}"
  return 0
}

verify_summary() {
  local total=$((CHECKS_PASSED + CHECKS_FAILED))
  echo
  if (( CHECKS_FAILED == 0 )); then
    printf '%s\n' "${C_GREEN}${C_BOLD}PASS${C_RESET} $CHECKS_PASSED/$total checks"
    return 0
  fi
  printf '%s\n' "${C_RED}${C_BOLD}NOT YET${C_RESET} $CHECKS_PASSED/$total checks passed - keep going!"
  return 1
}

# jp NAMESPACE RESOURCE JSONPATH -- shorthand for reading one field.
jp() { k -n "$1" get "$2" -o jsonpath="$3" 2>/dev/null; }
