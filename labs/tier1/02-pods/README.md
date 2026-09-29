# Lab t1-02: Pods: the smallest unit you run

**Curriculum:** [02b - Pods & Deployments](../../../curriculum/02-kubernetes-core/02b-pods-deployments.md) · **Time:** ~45 min

## Objectives
1. Create a pod **imperatively** (with a command) and **declaratively** (with YAML), and know
   when to use each.
2. Inspect pods with `get`, `describe`, `logs`, `exec` and `port-forward`.
3. Build a **multi-container pod** in which containers share a volume and a network.
4. Set resource **requests and limits**, and explain what each one does.
5. See for yourself that a bare pod is **not self-healing**.

> **Nutanix mapping**
> - A **pod** is the smallest thing Kubernetes schedules, like a VM is for AHV. The difference
>   is that a pod can hold several tightly coupled containers that share one IP address and can
>   share volumes, like several processes inside the same VM.
> - **Requests** are like reserving memory for a VM: the scheduler only places the pod on a
>   node that has that much unreserved.
> - **Limits** are a hard ceiling. A container that uses more memory than its limit is
>   OOM-killed.
> - A bare pod has **no HA**. If its node dies, nothing restarts it elsewhere. Lab t1-03 fixes
>   that with Deployments.

## Based on (official docs)
- Pods - <https://kubernetes.io/docs/concepts/workloads/pods/>
- Pod lifecycle (phases, restarts, CrashLoopBackOff) - <https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/>
- Resource management - <https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/>
- Debugging pods - <https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/>
- kubectl quick reference - <https://kubernetes.io/docs/reference/kubectl/quick-reference/>

## Setup
```bash
./labctl start t1-02
```

---

## Tasks

### Task 1 - Create a pod imperatively
```bash
kubectl -n lab-pods run web --image=nginx:1.29-alpine --labels=app=web,tier=frontend
kubectl -n lab-pods get pods                 # STATUS: ContainerCreating -> Running
kubectl -n lab-pods get pods -o wide         # IP address + which NODE it runs on
kubectl -n lab-pods get pods --show-labels
```
**Why `-n lab-pods` every time:** without it, kubectl uses the `default` namespace. Being
explicit about the namespace avoids "where did my pod go?" moments.

### Task 2 - Inspect it
```bash
kubectl -n lab-pods describe pod web     # read top to bottom: node, IP, containers, Events
kubectl -n lab-pods logs web             # stdout/stderr of the container
kubectl -n lab-pods get pod web -o yaml  # the full object: spec (what you asked for) + status (what is)
```
Look at `spec` and `status` in the YAML. **spec** is the desired state and **status** is the
observed state. Every Kubernetes object follows this pattern, including KubeVirt VMs later.

### Task 3 - Get inside it
```bash
kubectl -n lab-pods exec -it web -- sh      # a shell inside the container (type 'exit' to leave)
#   inside:  hostname; cat /etc/os-release; wget -qO- localhost | head -4; exit
kubectl -n lab-pods port-forward pod/web 8080:80
```
With `port-forward` running, open a second terminal and run `curl -s localhost:8080 | head -4`.
Press Ctrl+C in the first terminal to stop it.

**Why port-forward:** it tunnels through the API server to the pod. It's handy for debugging,
but it isn't how you expose apps; lab t1-04 covers Services for that.

### Task 4 - A multi-container pod, declaratively
Generate a starting point instead of typing YAML from scratch:
```bash
cd labs/tier1/02-pods/work
kubectl -n lab-pods run shared-demo --image=nginx:1.29-alpine --dry-run=client -o yaml > shared-demo.yaml
```
Edit `shared-demo.yaml` until it matches the version below. Type it rather than pasting, because
YAML indentation is a skill you need to build:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-demo
  namespace: lab-pods
  labels:
    app: shared-demo
spec:
  volumes:
  - name: html                 # a scratch volume that lives as long as the pod does
    emptyDir: {}
  containers:
  - name: web
    image: nginx:1.29-alpine
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html   # nginx serves files from here
  - name: writer                          # a "sidecar" that generates content
    image: busybox:1.37
    command: ["sh", "-c", "while true; do echo \"hello from the writer at $(date)\" > /data/index.html; sleep 5; done"]
    volumeMounts:
    - name: html
      mountPath: /data                    # same volume, different path
```
```bash
kubectl apply -f shared-demo.yaml
kubectl -n lab-pods get pod shared-demo          # READY 2/2
kubectl -n lab-pods exec shared-demo -c web -- wget -qO- http://localhost/
kubectl -n lab-pods logs shared-demo -c writer   # -c picks the container
```
**What to notice:** both containers see the same files through the shared volume. They also
share one network namespace, so `localhost` in one container is `localhost` in the other.

### Task 5 - Requests and limits
Add a `resources` block to **each** container in `shared-demo.yaml`:
```yaml
    resources:
      requests:
        cpu: 50m          # 50 millicores = 5% of one core, reserved for scheduling
        memory: 32Mi
      limits:
        memory: 64Mi      # hard cap; above this the container is OOM-killed
```
Now apply it:
```bash
kubectl apply -f shared-demo.yaml
```
**That fails, and the error is the lesson.** Most fields of a running pod are **immutable**.
Newer Kubernetes can resize the CPU and memory of a running pod in place through a separate
`resize` subresource, but a normal `apply` can't change them, and neither can adding resources to
a pod that had none. Delete the pod and create it again:
```bash
kubectl delete -f shared-demo.yaml
kubectl apply -f shared-demo.yaml
kubectl -n lab-pods get pod shared-demo -o jsonpath='{.status.qosClass}{"\n"}'   # Burstable
```
> **Why no CPU limit?** A CPU limit throttles the container even when the node has idle CPU,
> which often hurts latency. Many teams set CPU *requests* for scheduling and memory *limits*
> for safety. Read the "Resource management" page linked above and decide for yourself.

### Task 6 - Pods are not self-healing
```bash
kubectl -n lab-pods delete pod web
kubectl -n lab-pods get pods        # web is gone for good - nothing recreated it
```
Recreate it (Task 1 command) before you run verify. In lab t1-03 a **Deployment** takes over this
job, much as AHV HA restarts VMs after a host failure.

## Check your work
```bash
./labctl verify t1-02
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-02
```
Pod `api` keeps restarting. Your tools: `get -w`, `describe`, `logs --previous`.

<details><summary>Hint 1</summary>

`kubectl -n lab-pods get pod api`: note `CrashLoopBackOff` and the RESTARTS count. This state
means "the container keeps exiting, and Kubernetes waits longer before each restart".
</details>

<details><summary>Hint 2</summary>

`kubectl -n lab-pods logs api` shows the output of the latest attempt, and `--previous` shows the
attempt before it. If one of them says it can't retrieve the logs, try the other: the container
restarts quickly. The message is about a file.
</details>

<details><summary>Hint 3</summary>

The `command` overrides the image's normal start command and points nginx at a config file that
doesn't exist. Copy `breakfix/api.yaml` to `work/`, remove the `command:` line (the image's
default command runs stock nginx), then `kubectl delete pod api -n lab-pods` and
`kubectl apply -f work/api.yaml`.
</details>

Check: `./labctl breakfix t1-02 --check`

## Cleanup
```bash
./labctl cleanup t1-02
```

## Review questions
1. What's the difference between `spec` and `status`? Who writes each one?
2. Two containers in one pod: what do they share, and what don't they share?
3. When would you choose a multi-container pod over two separate pods?
4. What happens if a container goes over its memory **limit**? And over its CPU **limit**?
5. What does `CrashLoopBackOff` mean, and which command shows the logs of the crashed attempt?
6. Why did `kubectl apply` fail when you added `resources` to a running pod?
7. Your pod's node dies. What happens to a bare pod, and what would happen to a VM with AHV HA
   enabled?
