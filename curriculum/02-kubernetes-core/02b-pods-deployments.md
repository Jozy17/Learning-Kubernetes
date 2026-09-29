# 02b - Pods and Deployments

**Labs:** [t1-02 Pods](../../labs/tier1/02-pods/README.md) · [t1-03 Deployments](../../labs/tier1/03-deployments/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~30 min

## 1. Pods
A **pod** is the smallest thing Kubernetes schedules. It holds one or more containers that:
- run on the **same node**
- share **one network namespace**, and so one IP address; containers reach each other on
  `localhost`
- can share **volumes**
- are started, stopped and scheduled **together**

Most pods run one container. Extra containers are **sidecars** (log shippers, proxies, content
generators, as in lab t1-02) or **init containers**, which run to completion *before* the app
starts.

> **KubeVirt preview:** every running VM is a pod called `virt-launcher-<vm>-xxxxx`. Its main
> container runs QEMU. When you `kubectl get pods` in a Harvester namespace, you'll see one of
> these for each VM.

### Pod lifecycle
| Phase | Meaning |
|---|---|
| `Pending` | Accepted, but not running yet: waiting for scheduling, image pull or volumes |
| `Running` | Bound to a node; at least one container is running |
| `Succeeded` / `Failed` | All containers exited: all with 0, or at least one non-zero |
| `Unknown` | The node stopped reporting |

Common STATUS values you'll see in `kubectl get pods`, which are container states rather than
phases:
- `ContainerCreating`: pulling the image or mounting volumes
- `ImagePullBackOff` / `ErrImagePull`: the image can't be fetched (lab t1-01 break/fix)
- `CrashLoopBackOff`: the container keeps exiting, and restarts are delayed exponentially, up to
  5 minutes (lab t1-02 break/fix)
- `CreateContainerConfigError`: a referenced ConfigMap or Secret is missing (lab t1-05)
- `Running` but `0/1 READY`: the process is up but failing its **readiness probe** (lab t1-03)

### Pods are mortal and mostly immutable
- A bare pod is **never** rescheduled onto another node when its node dies. Controllers
  (Deployments, StatefulSets, DaemonSets, Jobs, and KubeVirt's VM controller) create
  replacements.
- Most of a pod's spec can't be changed after creation. You replace pods; you don't edit them.

### Resources: requests and limits
| | Requests | Limits |
|---|---|---|
| Used by | The **scheduler** (placement) | The **kubelet/kernel** (enforcement) |
| CPU | Guaranteed share | Throttled above it |
| Memory | Guaranteed for placement | **OOM-killed** above it |
| Nutanix analogy | Memory reservation for a VM | A hard ceiling (AHV doesn't overcommit memory by default) |

The resulting **QoS class** is Guaranteed (requests = limits for every container), Burstable, or
BestEffort (nothing set). Under memory pressure, BestEffort pods are evicted first.

### Probes
- **readiness**: "may this pod receive traffic?" Failing removes it from Service endpoints.
- **liveness**: "is it stuck?" Failing makes the kubelet restart the container.
- **startup**: "has it finished booting?" Liveness and readiness wait until it passes, which
  helps slow starters.

## 2. Deployments and ReplicaSets
```
Deployment (you write this)
   └── ReplicaSet  (one per pod-template version; name = deployment + hash)
         └── Pods  (N replicas stamped from the template)
```
- The **ReplicaSet controller** keeps exactly N pods matching its selector. That's the
  **self-healing** you saw in lab t1-03.
- The **Deployment controller** manages ReplicaSets: when the pod template changes, it creates a
  new ReplicaSet and shifts pods over gradually. That's a **rolling update**.
- `maxSurge` is how many extra pods may exist during an update. `maxUnavailable` is how many
  may be missing.
- Old ReplicaSets are kept, scaled to zero (up to `revisionHistoryLimit`, default 10), so
  `kubectl rollout undo` can switch back instantly.

### Other workload controllers (awareness)
| Controller | Use | Example |
|---|---|---|
| **StatefulSet** | Pods with stable identity and their own volumes | Databases, etcd |
| **DaemonSet** | One pod per node | Log agents, CNI, Longhorn's per-node components |
| **Job / CronJob** | Run to completion, optionally on a schedule | Backups, batch exports |

## 3. HA compared with Nutanix
| Situation | AHV | Kubernetes Deployment |
|---|---|---|
| Host fails | VM HA restarts the VM on another host (with the same disk) | ReplicaSet creates **new** pods elsewhere; the old ones are presumed dead after a timeout (about 5 min by default) |
| App process crashes | The guest OS may restart it | The kubelet restarts the container; liveness probes catch hangs |
| Planned maintenance | Live-migrate VMs off the host | Drain the node: pods are evicted and recreated elsewhere (with rolling replacement) |
| Scale out | Clone VMs | Change `replicas` |

KubeVirt VMs are closer to the AHV column. They're stateful and have one identity, so KubeVirt
**live-migrates** them during node drains when their storage allows it, as Longhorn RWX volumes
do in Harvester.

## Official docs
- Pods - <https://kubernetes.io/docs/concepts/workloads/pods/>
- Pod lifecycle - <https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/>
- Sidecar containers - <https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/>
- Resource management - <https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/>
- Probes - <https://kubernetes.io/docs/concepts/workloads/pods/probes/>
- Deployments - <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
- Workload management overview - <https://kubernetes.io/docs/concepts/workloads/controllers/>

## Key terms
pod · sidecar · init container · phase · CrashLoopBackOff · requests/limits · QoS class ·
readiness/liveness/startup probe · Deployment · ReplicaSet · rolling update · maxSurge ·
maxUnavailable · rollout undo · StatefulSet · DaemonSet · Job
