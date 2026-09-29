# Lab t1-03: Deployments: self-healing, scaling, rolling updates

**Curriculum:** [02b - Pods & Deployments](../../../curriculum/02-kubernetes-core/02b-pods-deployments.md) · **Time:** ~60 min

## Objectives
1. Write a Deployment manifest and explain the Deployment → ReplicaSet → Pod chain.
2. Watch a controller **self-heal**: delete pods and see them replaced.
3. Scale up and down.
4. Run a **rolling update**, watch it happen, look at its history, and roll it back.
5. Use a **readiness probe** so that traffic only reaches pods that are ready.

> **Nutanix mapping**
> - A **Deployment** is like a VM template, a desired count and AHV HA combined. You declare
>   "3 copies of this", and a **controller** constantly compares that with reality and fixes any
>   difference.
> - A **rolling update** is like a one-click AOS/AHV upgrade: it replaces instances one at a time
>   while keeping enough of them healthy. The difference is that here you roll *application
>   versions*, not hypervisors.
> - **Readiness probe:** think of how Prism won't mark a CVM healthy until its services respond.
>   A pod gets no traffic until its readiness probe passes.

## Based on (official docs)
- Deployments - <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
- ReplicaSet - <https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/>
- Liveness, readiness and startup probes - <https://kubernetes.io/docs/concepts/workloads/pods/probes/>
- Configure probes (task) - <https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/>
- `kubectl rollout` - <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/>

## Setup
```bash
./labctl start t1-03
```

---

## Tasks

### Task 1 - Write the Deployment
Generate a skeleton, then edit it:
```bash
cd labs/tier1/03-deployments/work
kubectl create deployment web --image=nginx:1.29-alpine --replicas=3 -n lab-deploy \
  --dry-run=client -o yaml > web-deployment.yaml
```
Edit `web-deployment.yaml` until it looks like this. The comments explain each part; you don't
need to type them.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: lab-deploy
  labels:
    app: web
spec:
  replicas: 3                     # desired state: always 3 pods
  selector:
    matchLabels:
      app: web                    # "the pods I own are the ones labelled app=web"
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                 # may create 1 extra pod during an update
      maxUnavailable: 0           # never drop below 3 ready pods during an update
  template:                       # the pod "template" - every replica is stamped from this
    metadata:
      labels:
        app: web                  # MUST match the selector above
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
        readinessProbe:           # only send traffic once nginx answers HTTP
          httpGet:
            path: /
            port: 80
          periodSeconds: 3
        resources:
          requests:
            cpu: 25m
            memory: 32Mi
          limits:
            memory: 64Mi
```
```bash
kubectl apply -f web-deployment.yaml
kubectl -n lab-deploy get deploy,rs,pods --show-labels
```
You'll see three layers. The **Deployment** owns a **ReplicaSet** (the name has a hash
suffix), and the ReplicaSet owns the **Pods**. Follow the chain yourself:
```bash
kubectl -n lab-deploy get pods -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"\n"}'
```

### Task 2 - Self-healing
Open a second terminal and watch:
```bash
kubectl -n lab-deploy get pods -w
```
In the first terminal, delete one pod:
```bash
kubectl -n lab-deploy delete pod $(kubectl -n lab-deploy get pods -l app=web -o name | head -1 | cut -d/ -f2)
```
A replacement appears within seconds. **Why:** the ReplicaSet controller saw 2 pods where you
asked for 3, and created one. This "observe → compare → act" loop is called **reconciliation**.
Every operator you'll meet works the same way, including KubeVirt and Harvester's own
controllers.

### Task 3 - Where did the pods land?
```bash
kubectl -n lab-deploy get pods -o wide        # spread across k8slab-worker / worker2
```
The scheduler usually spreads replicas across nodes. Later tiers cover forcing that
spread with anti-affinity, which is similar to AHV VM-VM anti-affinity rules.

### Task 4 - Scale
```bash
kubectl -n lab-deploy scale deployment web --replicas=5
kubectl -n lab-deploy get pods
kubectl -n lab-deploy scale deployment web --replicas=3
```
> Declarative vs imperative: `scale` changed the live object, but your YAML file still says 3.
> If the file said 2 and someone re-applied it, the change would be undone. In real teams the
> **file in git is the source of truth** (GitOps).

### Task 5 - Rolling update, history, rollback
In the watch terminal, run `kubectl -n lab-deploy get rs -w`. Then:
```bash
kubectl -n lab-deploy annotate deployment/web kubernetes.io/change-cause="upgrade nginx to 1.30" --overwrite
kubectl -n lab-deploy set image deployment/web nginx=nginx:1.30-alpine
kubectl -n lab-deploy rollout status deployment/web
kubectl -n lab-deploy rollout history deployment/web
```
Watch the new ReplicaSet scale up while the old one scales down, one pod at a time. The old
ReplicaSet is kept at 0 replicas so that you can roll back:
```bash
kubectl -n lab-deploy rollout undo deployment/web            # back to 1.29
kubectl -n lab-deploy get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n lab-deploy annotate deployment/web kubernetes.io/change-cause="re-apply nginx 1.30 after rollback test" --overwrite
kubectl -n lab-deploy rollout undo deployment/web            # and forward again to 1.30
kubectl -n lab-deploy rollout history deployment/web
```
**Why annotate first:** the `change-cause` is copied into the *new* ReplicaSet when it's
created. Revision numbers also move: an undo makes the old revision the newest one.

`rollout undo` prints a warning about `last-applied-configuration`. The warning says that the live
object no longer matches the last file you applied, which is the imperative-vs-declarative drift
from Task 4 again.
Finally, update the `image:` line in `work/web-deployment.yaml` to `nginx:1.30-alpine` so the file
matches the cluster again.

## Check your work
```bash
./labctl verify t1-03
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-03
```
Deployment `api` shows 0/3 ready, yet the pods are `Running`.

<details><summary>Hint 1</summary>

`Running` means the process started. `Ready` means the pod passed its readiness probe. They're
different conditions. Try `kubectl -n lab-deploy get events --field-selector reason=Unhealthy`
and `kubectl -n lab-deploy describe pod -l app=api | grep Readiness`.
</details>

<details><summary>Hint 2</summary>

Which port does the probe check, and which port does nginx listen on?
</details>

<details><summary>Hint 3</summary>

`kubectl -n lab-deploy edit deployment api` (or `kubectl patch`): set the probe's `port` to `80`.
The Deployment rolls out new pods with the corrected probe. Deleting the probe would also make
the pods "Ready", but then broken pods would get traffic too, so the check rejects that fix.
</details>

Check: `./labctl breakfix t1-03 --check`

## Cleanup
```bash
./labctl cleanup t1-03
```

## Review questions
1. Name the three objects in the Deployment → ... → Pod chain. Which controller manages each
   step?
2. What would happen if the pod template's labels didn't match `spec.selector`?
3. With `replicas: 3`, `maxSurge: 1`, `maxUnavailable: 0`, what is the most pods that can exist
   during an update? What is the fewest *ready* pods?
4. Why did `rollout undo` work? What object makes it possible?
5. A pod is `Running` but `0/1 READY`. What does that tell you, and where do you look next?
6. Why is removing a failing readiness probe a bad fix?
7. Compare a Deployment with AHV HA. What does each one protect against, and what doesn't it
   protect against?
