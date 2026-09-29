# Lab t1-05: Namespaces, quotas, ConfigMaps and Secrets

**Curriculum:** [02d - Namespaces, Config & Secrets](../../../curriculum/02-kubernetes-core/02d-namespaces-config-secrets.md) · **Time:** ~60 min

## Objectives
1. Use a namespace as a unit of **resource governance**, with a ResourceQuota and a LimitRange.
2. Keep configuration **out of images** with ConfigMaps, and consume them as env vars and files.
3. Create a Secret, and prove to yourself that base64 is **encoding, not encryption**.
4. Mount secrets as read-only **files** rather than env vars, and explain why.
5. Diagnose a pod that is waiting for configuration that doesn't exist.

> **Nutanix mapping**
> - A **namespace + ResourceQuota** is like a Prism Central **Project** with quotas: a team gets
>   a bounded slice of the cluster.
> - A **LimitRange** is like a default VM size in a template: you get it unless you ask for
>   something different.
> - **ConfigMaps/Secrets:** Nutanix has no direct equivalent. The nearest idea is guest
>   customisation (cloud-init / Sysprep) data that is kept *separate* from the disk image. The
>   same image runs anywhere, and only the config changes. Harvester uses this idea too, storing
>   VM cloud-init user data in Secrets.

## Based on (official docs)
- Namespaces - <https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/>
- Resource quotas - <https://kubernetes.io/docs/concepts/policy/resource-quotas/>
- Limit ranges - <https://kubernetes.io/docs/concepts/policy/limit-range/>
- ConfigMaps - <https://kubernetes.io/docs/concepts/configuration/configmap/>
- Secrets - <https://kubernetes.io/docs/concepts/configuration/secret/>
- Good practices for Secrets - <https://kubernetes.io/docs/concepts/security/secrets-good-practices/>

## Setup
```bash
./labctl start t1-05
```

---

## Tasks

### Task 1 - Govern the namespace
Create `work/governance.yaml`:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: lab-config
spec:
  hard:
    pods: "10"
    requests.cpu: "1"         # total CPU all pods together may REQUEST
    requests.memory: 1Gi
    limits.memory: 2Gi
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-resources
  namespace: lab-config
spec:
  limits:
  - type: Container
    defaultRequest:           # applied when a container specifies no requests
      cpu: 50m
      memory: 32Mi
    default:                  # applied when a container specifies no limits
      memory: 64Mi
```
```bash
kubectl apply -f labs/tier1/05-config-secrets/work/governance.yaml
kubectl -n lab-config describe resourcequota compute-quota
```
**Why both:** once a quota covers `requests.cpu`, every pod *must* declare CPU requests or the
API server rejects it. The LimitRange fills in sensible defaults, so pods without explicit
resources still get admitted.

Try going over the quota:
```bash
kubectl -n lab-config create deployment hog --image=busybox:1.37 --replicas=0 -- sleep infinity
kubectl -n lab-config set resources deployment hog --requests=cpu=500m   # each pod asks for half a CPU
kubectl -n lab-config scale deployment hog --replicas=3
kubectl -n lab-config get deploy hog                 # stuck at 2/3: 2 x 500m = the whole 1-CPU quota
kubectl -n lab-config get events --field-selector reason=FailedCreate | tail -3   # "exceeded quota"
kubectl -n lab-config delete deployment hog
kubectl -n lab-config get pods -w     # Ctrl+C once the hog pods are gone (~30 s)
```
**Why the wait:** `sleep` running as PID 1 ignores the polite stop signal (SIGTERM), so each
pod is only killed after the 30-second grace period. **Terminating pods still count against the
quota**, so if you create the next pod too soon it will be rejected.

### Task 2 - ConfigMap from literals and from a file
```bash
cat > labs/tier1/05-config-secrets/work/app.properties <<'EOF'
greeting=hello
feature.newUI=true
EOF
kubectl -n lab-config create configmap app-config \
  --from-literal=APP_MODE=training \
  --from-literal=APP_COLOR=blue \
  --from-file=labs/tier1/05-config-secrets/work/app.properties
kubectl -n lab-config get configmap app-config -o yaml
```

### Task 3 - A Secret, and why base64 isn't protection
The values below are **lab placeholders**. Never put real credentials in commands (they end up
in shell history) or in git.
```bash
kubectl -n lab-config create secret generic db-credentials \
  --from-literal=username=labuser \
  --from-literal=password='CHANGE_ME_lab_only'
kubectl -n lab-config get secret db-credentials -o yaml          # values look scrambled...
kubectl -n lab-config get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
```
...but anyone with `get secret` permission can decode them instantly.

> **How Secrets are really protected:**
> 1. **RBAC** controls who may read Secrets (lab t1-07).
> 2. **Encryption at rest** encrypts Secrets in etcd. It's a cluster setting, not the default in
>    plain Kubernetes.
> 3. **External secret managers**, such as Vault or a cloud KMS, synced in with operators.
>
> This comes up in security audits of Harvester too: VM cloud-init user data, which can contain
> passwords, is stored in Secrets.

### Task 4 - Consume config in a pod
Write `work/app-pod.yaml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: lab-config
spec:
  containers:
  - name: app
    image: busybox:1.37
    command: ["sh", "-c", "echo mode=$APP_MODE; sleep infinity"]
    env:
    - name: APP_MODE                # one key from the ConfigMap as an env var
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_MODE
    volumeMounts:
    - name: app-config-files
      mountPath: /etc/app           # every ConfigMap key becomes a file here
    - name: db-creds
      mountPath: /etc/db
      readOnly: true
    # no resources block: the LimitRange from Task 1 fills in defaults
  volumes:
  - name: app-config-files
    configMap:
      name: app-config
  - name: db-creds
    secret:
      secretName: db-credentials
      defaultMode: 0400             # owner-read-only files
```
```bash
kubectl apply -f labs/tier1/05-config-secrets/work/app-pod.yaml
kubectl -n lab-config logs app
kubectl -n lab-config exec app -- ls -l /etc/app /etc/db
kubectl -n lab-config exec app -- cat /etc/app/app.properties
kubectl -n lab-config get pod app -o jsonpath='{.spec.containers[0].resources}{"\n"}'   # LimitRange defaults
```
> **Why files instead of env vars for secrets?** Environment variables leak easily. They're
> inherited by child processes, printed by crash dumps and debug endpoints, and visible in
> `/proc/<pid>/environ`. Files can have tight permissions, and the kubelet updates them in place
> when the Secret changes.

### Task 5 - Live updates: files yes, env no
```bash
kubectl -n lab-config create configmap app-config --from-literal=APP_MODE=production \
  --from-literal=APP_COLOR=blue --from-file=labs/tier1/05-config-secrets/work/app.properties \
  --dry-run=client -o yaml | kubectl apply -f -
# wait ~60s (the kubelet sync period), then:
kubectl -n lab-config exec app -- cat /etc/app/APP_MODE      # production (file updated)
kubectl -n lab-config exec app -- printenv APP_MODE          # training   (env is fixed at start)
```
Env vars are read once, when the container starts. Put the value back to `training` (repeat the
command with `APP_MODE=training`) before you verify.

> The `create ... --dry-run=client -o yaml | kubectl apply -f -` pattern is a common idiom for
> "create or update".

## Check your work
```bash
./labctl verify t1-05
```
Verify checks that `printenv APP_MODE` says `training`. If you changed it in Task 5, restore the
ConfigMap and recreate the pod:
`kubectl delete -f .../app-pod.yaml && kubectl apply -f .../app-pod.yaml`.

---

## Break/fix scenario
```bash
./labctl breakfix t1-05
```
Pod `worker` never starts. You may **not** delete or edit the pod.

<details><summary>Hint 1</summary>

`kubectl -n lab-config get pod worker` shows `CreateContainerConfigError`. `describe` tells you
exactly what's missing.
</details>

<details><summary>Hint 2</summary>

The pod refers to ConfigMap `worker-settings`, key `LOG_LEVEL`. Create it:
`kubectl -n lab-config create configmap worker-settings --from-literal=LOG_LEVEL=info`.
The kubelet keeps retrying, so the pod starts by itself within a few seconds.
</details>

Check: `./labctl breakfix t1-05 --check`

## Cleanup
```bash
./labctl cleanup t1-05
```

## Review questions
1. Why does a ResourceQuota on `requests.cpu` usually need a LimitRange next to it?
2. What's the difference between a ConfigMap and a Secret, technically and in how you handle
   them?
3. Someone says "our secrets are safe because they're base64-encoded". How do you answer?
4. List three controls that actually protect Secrets in Kubernetes.
5. Why prefer mounting a secret as a file over putting it in an environment variable?
6. You change a ConfigMap. Which consumers see the change without a restart, and which don't?
7. What does `CreateContainerConfigError` usually mean?
