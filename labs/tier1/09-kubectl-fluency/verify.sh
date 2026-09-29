#!/usr/bin/env bash
# Lab t1-09 verify
set -o errexit -o nounset -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../../../lib/common.sh"
source "$DIR/lab.env"
require_cluster
NS="$LAB_NAMESPACE"

check "The failed pod is labelled triage=needed" \
  test "$(jp "$NS" pod/nightly-export-7f3kq '{.metadata.labels.triage}')" = needed
hint "Task 3: kubectl get pods --field-selector=status.phase=Failed"
check "No healthy pod is labelled triage=needed" \
  test -z "$(k -n "$NS" get pods -l triage=needed --field-selector=status.phase!=Failed -o name)"
check "The Deployment on the old nginx image is annotated upgrade=pending" \
  test "$(jp "$NS" deployment/reporting '{.metadata.annotations.upgrade}')" = pending
hint "Task 4: custom-columns or jsonpath to show every Deployment's image"
check "Only that Deployment carries upgrade=pending" \
  test "$(k -n "$NS" get deploy -o jsonpath='{range .items[*]}{.metadata.annotations.upgrade}{"\n"}{end}' | grep -c pending)" = 1
check "Deployment report exists with label team=ops" \
  test "$(jp "$NS" deployment/report '{.metadata.labels.team}')" = ops
hint "Task 5: generate with --dry-run=client -o yaml, edit, apply"
check "report has 3 replicas (changed via file + kubectl diff + apply)" \
  test "$(jp "$NS" deployment/report '{.spec.replicas}')" = 3
check "report was applied from a file (has last-applied-configuration)" \
  test -n "$(jp "$NS" deployment/report '{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}')"
hint "use kubectl apply -f (not create) so the object remembers the file"
check "Every Deployment labelled tier=cache runs 2 replicas" \
  test "$(k -n "$NS" get deploy -l tier=cache -o jsonpath='{range .items[*]}{.spec.replicas}{end}')" = 2
hint "Task 6: kubectl scale deployment -l tier=cache --replicas=2"
check "backend keeps only 3 old ReplicaSets (revisionHistoryLimit: 3)" \
  test "$(jp "$NS" deployment/backend '{.spec.revisionHistoryLimit}')" = 3
hint "Task 7: kubectl patch ... --type=merge"

verify_summary
