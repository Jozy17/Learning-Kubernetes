# 02a - Kubernetes architecture and kubectl

**Labs:** all of Tier 1 · [t1-09 kubectl fluency](../../labs/tier1/09-kubectl-fluency/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~30 min

## 1. The one idea: desired state + reconciliation

In Prism you mostly **do** things: "create VM", "power on", "migrate". In Kubernetes you mostly
**declare** things: "there should be 3 of these, with this image, reachable on this port". Then
**controllers** work continuously to make reality match. They observe, compare and act, again
and again.

Every object therefore has two halves:
- **`spec`** is what you want. You or your tools write it.
- **`status`** is what currently is. Controllers write it.

Once this idea clicks, KubeVirt makes sense: a `VirtualMachine` object whose `spec` says
`running` is a VM that the cluster keeps running.

## 2. The parts of a cluster

```
                    ┌──────────────── control plane ────────────────┐
  kubectl ─HTTPS──▶ │ kube-apiserver ◀──▶ etcd (the database)       │
  (you)             │      ▲   ▲                                    │
                    │      │   └── kube-scheduler (picks a node)    │
                    │      └────── kube-controller-manager          │
                    │               (Deployment, ReplicaSet, ...    │
                    │                controllers)                   │
                    └──────▲────────────────────────────────────────┘
                           │ watch / report
     ┌─────── node ────────┴──┐   ┌─────── node ──────────┐
     │ kubelet ─CRI─▶ containerd│   │ kubelet ─▶ containerd │
     │ kube-proxy, CNI (network)│   │ kube-proxy, CNI       │
     │ pods...                  │   │ pods...               │
     └──────────────────────────┘   └───────────────────────┘
```

| Component | What it does | Nutanix analogy |
|---|---|---|
| **kube-apiserver** | The only front door. Every read and write goes through its REST API, with authentication, authorization (RBAC) and validation | Prism's API gateway |
| **etcd** | A consistent key-value store holding every object | The cluster configuration database (Zeus/Zookeeper in the CVMs) |
| **kube-scheduler** | Chooses a node for each new pod, based on resources, affinity and taints | Acropolis's VM placement / ADS initial placement |
| **kube-controller-manager** | Runs the built-in controllers (ReplicaSet, Deployment, Node, Job, ...) | The Acropolis leader's "keep things as configured" logic |
| **kubelet** | The agent on each node. It makes that node's pods real and reports status | The AHV host agent |
| **Container runtime** (containerd) | Starts and stops containers | The hypervisor (AHV/KVM) for VMs |
| **CNI plugin** | Gives pods IPs and connectivity (kindnet here, Canal in Harvester) | The OVS networking on AHV |
| **kube-proxy** | Implements Service virtual IPs on each node | Distributed load-balancing rules |

**Harvester is Kubernetes.** It's an RKE2 cluster: RKE2 runs these same components as static
pods plus containerd, with KubeVirt, Longhorn, Multus and Harvester's own controllers added on
top. Harvester's "management nodes" are its control-plane nodes, and in a 3+ node cluster three
of them run etcd. Tier 3 goes into detail.

## 3. Objects you'll use daily

| Object | Purpose | Lab |
|---|---|---|
| Pod | One or more containers scheduled together | t1-02 |
| Deployment → ReplicaSet | Keep N identical pods running; rolling updates | t1-03 |
| Service, EndpointSlice | A stable VIP + DNS name in front of pods | t1-04 |
| Namespace, ResourceQuota, LimitRange | Scoping and governance | t1-05 |
| ConfigMap, Secret | Configuration kept outside the image | t1-05 |
| PV, PVC, StorageClass | Persistent storage | t1-06 |
| ServiceAccount, Role(Binding), ClusterRole(Binding) | Identity and access | t1-07 |
| CustomResourceDefinition | New object types (KubeVirt, Harvester, Longhorn...) | t1-08 |

All objects share the same envelope:
```yaml
apiVersion: apps/v1        # API group/version
kind: Deployment           # object type
metadata:                  # name, namespace, labels, annotations, ownerReferences, finalizers
  name: web
  namespace: shop
spec: {...}                # desired state
status: {...}              # observed state (read-only for you)
```

## 4. kubectl: the essentials

`kubectl` talks to the API server using a **kubeconfig** file (`~/.kube/config`), which holds:
- **clusters**: API server URLs and CA certificates
- **users**: credentials (client certificates, tokens, OIDC)
- **contexts**: a cluster + user + default namespace. `kubectl config use-context` switches
  between them.

> **Safety habit:** the labs always pass `--context kind-k8slab`, so they can never touch
> another cluster. When you have production Harvester contexts, check
> `kubectl config current-context` before any `delete`.

### Command patterns
| Goal | Command |
|---|---|
| List | `kubectl get pods -n NS` · `-A` (all namespaces) · `-o wide` · `--show-labels` |
| Inspect | `kubectl describe pod X` (includes **Events**!) · `kubectl get pod X -o yaml` |
| Logs / shell | `kubectl logs X [-c container] [--previous]` · `kubectl exec -it X -- sh` |
| Create or update from a file | `kubectl apply -f file.yaml` (declarative, repeatable) |
| Preview a change | `kubectl diff -f file.yaml` |
| Generate YAML | `kubectl create deployment X --image=I --dry-run=client -o yaml` |
| Filter | `-l app=web` (labels) · `--field-selector status.phase=Failed` |
| Format | `-o jsonpath='{.items[*].metadata.name}'` · `-o custom-columns=...` · `--sort-by=` |
| Built-in docs | `kubectl explain deployment.spec.strategy` |
| Permission check | `kubectl auth can-i delete pods --as=...` |
| Watch | `kubectl get pods -w` |

### Imperative vs declarative
- **Imperative** (`run`, `create`, `scale`, `set image`, `edit`): quick, and good for learning
  and emergencies. But the change lives only in the cluster.
- **Declarative** (`apply -f` with files in git): repeatable, reviewable and auditable. This is
  how teams run production, often through **GitOps** tools such as Fleet (built into Rancher) or
  Argo CD.

### The debugging ladder
When something's wrong, go down this list in order:
1. `kubectl get <thing>`: what's the STATUS?
2. `kubectl describe <thing>`: read the **Events** at the bottom.
3. `kubectl logs <pod> [--previous]`: what did the app say?
4. `kubectl get events -n NS --sort-by=.lastTimestamp`: what happened around it?
5. Follow the ownership chain: pod → ReplicaSet → Deployment, or PVC → PV → StorageClass.

## Official docs
- Cluster architecture - <https://kubernetes.io/docs/concepts/architecture/>
- Kubernetes components - <https://kubernetes.io/docs/concepts/overview/components/>
- Objects in Kubernetes - <https://kubernetes.io/docs/concepts/overview/working-with-objects/>
- kubectl quick reference - <https://kubernetes.io/docs/reference/kubectl/quick-reference/>
- Organizing cluster access (kubeconfig) - <https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/>
- RKE2 architecture - <https://docs.rke2.io/architecture>

## Key terms
desired state · reconciliation · spec/status · control plane · etcd · kubelet · scheduler ·
controller · kubeconfig · context · declarative/imperative · Events
