#!/usr/bin/env bash
# ============================================================================
#  SPOILERS: this script contains the SOLUTIONS to every Tier 1 lab and
#  break/fix scenario. Do the labs yourself first!
# ============================================================================
# End-to-end regression test for Tier 1. For every lab it runs:
#   setup (twice, to prove idempotency) -> solution -> verify must PASS
#   -> breakfix inject -> check must FAIL -> fix -> check must PASS
#   -> cleanup (twice)
# Use it after bumping versions.env. Usage:
#   tests/e2e-tier1.sh            # all labs, reusing the cluster if it exists
#   tests/e2e-tier1.sh t1-04      # a single lab
#   FRESH=1 tests/e2e-tier1.sh    # delete + recreate the cluster first
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/common.sh"
L="$ROOT/labctl"
FAILS=()

# Run a block of commands quietly, but show the output if it fails.
quiet() { local out; if ! out="$("$@" 2>&1)"; then echo "$out"; return 1; fi; }
must_pass() { quiet "$L" "$@" || { FAILS+=("$*"); warn "FAILED: labctl $*"; }; }
must_fail() { if quiet "$L" "$@"; then FAILS+=("$* (expected failure)"); warn "UNEXPECTED PASS: labctl $*"; fi; }
yaml_block() { awk -v n="$2" '/^```yaml$/{c++; if(c==n){f=1; next}} f&&/^```$/{exit} f{print}' "$1"; }

run_lab() {
  local id="$1"; info "=== $id ==="
  must_pass cleanup "$id"
  must_pass start "$id"; must_pass start "$id"
  "solve_${id//-/_}"
  must_pass verify "$id"
  must_pass breakfix "$id"
  sleep 3
  must_fail breakfix "$id" --check
  "fix_${id//-/_}"
  must_pass breakfix "$id" --check
  must_pass cleanup "$id"; must_pass cleanup "$id"
}

# ---------------- t1-01 ----------------
solve_t1_01() {
  local w="$ROOT/labs/tier1/01-containers/work"
  echo '<h1>Hello from my first container image</h1>' > "$w/index.html"
  printf 'FROM busybox:1.37\nCOPY index.html /www/index.html\nEXPOSE 8080\nUSER 65534\nCMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]\n' > "$w/Dockerfile"
  docker build -q -t hello-web:1.0 "$w" >/dev/null
  docker tag hello-web:1.0 localhost:5001/hello-web:1.0 && docker push -q localhost:5001/hello-web:1.0 >/dev/null
  kind load docker-image hello-web:1.0 --name "$CLUSTER_NAME" >/dev/null 2>&1
  k -n lab-containers run hello-web --image=hello-web:1.0 --port=8080 >/dev/null
  k -n lab-containers wait --for=condition=Ready pod/hello-web --timeout=90s >/dev/null
}
fix_t1_01() {
  local w="$ROOT/labs/tier1/01-containers/work"
  echo '<h1>Hello from v2</h1>' > "$w/index.html"
  docker build -q -t hello-web:2.0 "$w" >/dev/null
  kind load docker-image hello-web:2.0 --name "$CLUSTER_NAME" >/dev/null 2>&1
  k -n lab-containers delete pod hello-v2 --wait=true >/dev/null
  k apply -f "$ROOT/labs/tier1/01-containers/breakfix/hello-v2.yaml" >/dev/null
  k -n lab-containers wait --for=condition=Ready pod/hello-v2 --timeout=90s >/dev/null
}

# ---------------- t1-02 ----------------
solve_t1_02() {
  local r="$ROOT/labs/tier1/02-pods/README.md"
  k -n lab-pods run web --image="$IMG_NGINX_OLD" --labels=app=web,tier=frontend >/dev/null
  yaml_block "$r" 1 | python3 -c '
import sys; s=sys.stdin.read()
r="    resources:\n      requests:\n        cpu: 50m\n        memory: 32Mi\n      limits:\n        memory: 64Mi\n"
s=s.replace("      mountPath: /usr/share/nginx/html   # nginx serves files from here\n","      mountPath: /usr/share/nginx/html\n"+r)
s=s.replace("      mountPath: /data                    # same volume, different path\n","      mountPath: /data\n"+r)
print(s)' | k apply -f - >/dev/null
  k -n lab-pods wait --for=condition=Ready pod/web pod/shared-demo --timeout=90s >/dev/null
}
fix_t1_02() {
  k -n lab-pods delete pod api --wait=true >/dev/null
  grep -v 'command:' "$ROOT/labs/tier1/02-pods/breakfix/api.yaml" | k apply -f - >/dev/null
  k -n lab-pods wait --for=condition=Ready pod/api --timeout=90s >/dev/null
}

# ---------------- t1-03 ----------------
solve_t1_03() {
  local r="$ROOT/labs/tier1/03-deployments/README.md"
  yaml_block "$r" 1 | k apply -f - >/dev/null
  k -n lab-deploy rollout status deploy/web --timeout=120s >/dev/null
  k -n lab-deploy annotate deploy/web kubernetes.io/change-cause="upgrade nginx to 1.30" --overwrite >/dev/null
  k -n lab-deploy set image deploy/web nginx="$IMG_NGINX_NEW" >/dev/null
  k -n lab-deploy rollout status deploy/web --timeout=120s >/dev/null
}
fix_t1_03() {
  k -n lab-deploy patch deploy api --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]' >/dev/null
  k -n lab-deploy rollout status deploy/api --timeout=120s >/dev/null
}

# ---------------- t1-04 ----------------
solve_t1_04() {
  local r="$ROOT/labs/tier1/04-services-networking/README.md"
  k -n lab-net expose deployment web --port=80 --target-port=80 >/dev/null
  yaml_block "$r" 1 | k apply -f - >/dev/null
  yaml_block "$r" 2 | k apply -f - >/dev/null
  sleep 3
}
fix_t1_04() {
  k -n lab-net patch svc api --type=merge -p '{"spec":{"selector":{"app":"api"}}}' >/dev/null
  k -n lab-net patch svc api --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]' >/dev/null
  sleep 3
}

# ---------------- t1-05 ----------------
solve_t1_05() {
  local r="$ROOT/labs/tier1/05-config-secrets/README.md" w="$ROOT/labs/tier1/05-config-secrets/work"
  yaml_block "$r" 1 | k apply -f - >/dev/null
  printf 'greeting=hello\nfeature.newUI=true\n' > "$w/app.properties"
  k -n lab-config create configmap app-config --from-literal=APP_MODE=training \
    --from-literal=APP_COLOR=blue --from-file="$w/app.properties" >/dev/null
  k -n lab-config create secret generic db-credentials --from-literal=username=labuser \
    --from-literal=password='CHANGE_ME_lab_only' >/dev/null
  yaml_block "$r" 2 | k apply -f - >/dev/null
  k -n lab-config wait --for=condition=Ready pod/app --timeout=90s >/dev/null
}
fix_t1_05() {
  k -n lab-config create configmap worker-settings --from-literal=LOG_LEVEL=info >/dev/null
  wait_for "worker running" 90 bash -c "[[ \$(kubectl --context $KUBE_CONTEXT -n lab-config get pod worker -o jsonpath='{.status.phase}') == Running ]]"
}

# ---------------- t1-06 ----------------
solve_t1_06() {
  local r="$ROOT/labs/tier1/06-storage/README.md"
  yaml_block "$r" 1 | k apply -f - >/dev/null
  yaml_block "$r" 2 | k apply -f - >/dev/null
  k -n lab-storage wait --for=condition=Ready pod/writer --timeout=120s >/dev/null
  k -n lab-storage delete pod writer --wait=true >/dev/null
  yaml_block "$r" 2 | sed -e 's/name: writer/name: reader/' -e 's/^    command: .*/    command: ["sleep", "infinity"]/' | k apply -f - >/dev/null
  k -n lab-storage wait --for=condition=Ready pod/reader --timeout=120s >/dev/null
  yaml_block "$r" 3 | k apply -f - >/dev/null
  sleep 2
}
fix_t1_06() {
  printf 'apiVersion: storage.k8s.io/v1\nkind: StorageClass\nmetadata: {name: fast-ssd}\nprovisioner: rancher.io/local-path\nvolumeBindingMode: WaitForFirstConsumer\nreclaimPolicy: Delete\n' | k apply -f - >/dev/null
  k -n lab-storage rollout status deploy/db --timeout=180s >/dev/null
  sleep 3
}

# ---------------- t1-07 ----------------
solve_t1_07() {
  local r="$ROOT/labs/tier1/07-rbac/README.md"
  k -n lab-rbac create serviceaccount auditor >/dev/null
  k -n lab-rbac create role pod-reader --verb=get,list,watch --resource=pods,pods/log >/dev/null
  k -n lab-rbac create rolebinding auditor-pod-reader --role=pod-reader --serviceaccount=lab-rbac:auditor >/dev/null
  yaml_block "$r" 1 | k apply -f - >/dev/null
  k -n lab-rbac create serviceaccount viewer >/dev/null
  k -n lab-rbac create rolebinding viewer-view --clusterrole=view --serviceaccount=lab-rbac:viewer >/dev/null
}
fix_t1_07() {
  k -n lab-rbac patch rolebinding ci-bot-binding --type=json -p='[{"op":"replace","path":"/subjects/0/namespace","value":"lab-rbac"}]' >/dev/null
  k -n lab-rbac patch role ci-deployer --type=json -p='[{"op":"add","path":"/rules/0/verbs/-","value":"patch"}]' >/dev/null
}

# ---------------- t1-08 ----------------
solve_t1_08() {
  local r="$ROOT/labs/tier1/08-crds-operators/README.md" d="$ROOT/labs/tier1/08-crds-operators"
  yaml_block "$r" 1 | k apply -f - >/dev/null
  k wait --for=condition=Established crd/vmrequests.lab.example.com --timeout=60s >/dev/null
  yaml_block "$r" 2 | k apply -f - >/dev/null
  "$d/controller.sh" --once >/dev/null
  k -n lab-crd patch vmr web-01 --type=merge -p '{"spec":{"memoryGi":8}}' >/dev/null
  "$d/controller.sh" --once >/dev/null
  k -n lab-crd delete vmr db-01 --wait=true >/dev/null
  wait_for "GC of db-01-vm" 60 bash -c "! kubectl --context $KUBE_CONTEXT -n lab-crd get configmap db-01-vm"
}
fix_t1_08() {
  k -n lab-crd patch vmr legacy-01 --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null
  sleep 2
}

# ---------------- t1-09 ----------------
solve_t1_09() {
  local n="-n lab-kubectl"
  # shellcheck disable=SC2086
  {
    k $n label pod nightly-export-7f3kq triage=needed >/dev/null
    k $n annotate deployment reporting upgrade=pending >/dev/null
    k $n create deployment report --image="$IMG_NGINX_NEW" --replicas=2 --dry-run=client -o yaml \
      | sed 's/^    app: report$/    app: report\n    team: ops/' | awk '!(/team: ops/ && seen++)' | k apply -f - >/dev/null
    k $n create deployment report --image="$IMG_NGINX_NEW" --replicas=3 --dry-run=client -o yaml \
      | sed 's/^    app: report$/    app: report\n    team: ops/' | awk '!(/team: ops/ && seen++)' | k apply -f - >/dev/null
    k $n scale deployment -l tier=cache --replicas=2 >/dev/null
    k $n patch deployment backend --type=merge -p '{"spec":{"revisionHistoryLimit":3}}' >/dev/null
  }
}
fix_t1_09() { kubectl config set-context "$KUBE_CONTEXT" --namespace=lab-kubectl >/dev/null; }

# ---------------- main ----------------
if [[ "${FRESH:-0}" == 1 ]]; then "$L" cluster down; fi
"$L" cluster up >/dev/null
labs=("$@"); [[ ${#labs[@]} -gt 0 ]] || labs=(t1-01 t1-02 t1-03 t1-04 t1-05 t1-06 t1-07 t1-08 t1-09)
for id in "${labs[@]}"; do run_lab "$id"; done

echo
if (( ${#FAILS[@]} == 0 )); then ok "E2E PASS: ${labs[*]}"; else
  warn "E2E FAILURES:"; printf '  - %s\n' "${FAILS[@]}"; exit 1
fi
