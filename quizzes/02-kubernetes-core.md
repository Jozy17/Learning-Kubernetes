# Quiz 02 - Kubernetes core

Source: [curriculum/02-kubernetes-core/](../curriculum/02-kubernetes-core/README.md) and labs t1-02 … t1-09.
Run with `./labctl quiz 02`, and use `--missed` to review only the cards you got wrong.

### Q: What's the difference between `spec` and `status`, and who writes each one?
**A:** `spec` is the desired state, written by you or your tools. `status` is the observed state, written by controllers.

### Q: What does the kube-apiserver do, and which component stores cluster state?
**A:** The API server is the single front door: it authenticates, authorizes, validates and serves every request. etcd stores all objects.

### Q: What does the kube-scheduler decide? What does the kubelet do?
**A:** The scheduler picks a node for each new pod. The kubelet on that node makes the pod real (through the runtime) and reports its status.

### Q: What is a kubeconfig context?
**A:** A named combination of a cluster, a user (credentials) and an optional default namespace. `kubectl config use-context` switches between them.

### Q: Two containers in one pod: what do they share?
**A:** The node, the network namespace (one IP, and `localhost` between them) and any volumes they both mount. Each has its own filesystem image and process space by default.

### Q: A pod shows `CrashLoopBackOff`. What does it mean, and which command shows the crashed attempt's output?
**A:** The container keeps exiting, and restarts are delayed with growing back-off. Run `kubectl logs <pod> --previous` (and `describe` for events).

### Q: A pod is `Running` but `0/1 READY`. What does that tell you?
**A:** The process is up, but the readiness probe is failing, so the pod is removed from Service endpoints and gets no traffic.

### Q: Readiness vs liveness probe: what does each one do when it fails?
**A:** A failing readiness probe removes the pod from Service endpoints. A failing liveness probe makes the kubelet restart the container.

### Q: What happens when a container exceeds its memory limit? Its CPU limit?
**A:** Memory: it is OOM-killed. CPU: it is throttled.

### Q: What are the three QoS classes, and which is evicted first under memory pressure?
**A:** Guaranteed, Burstable and BestEffort. BestEffort (no requests or limits) is evicted first.

### Q: Name the chain of objects a Deployment manages.
**A:** Deployment → ReplicaSet (one per pod-template version) → Pods.

### Q: With replicas 3, maxSurge 1 and maxUnavailable 0, what are the most total pods and the fewest ready pods during a rolling update?
**A:** Up to 4 pods in total, and never fewer than 3 ready.

### Q: What makes `kubectl rollout undo` possible?
**A:** Old ReplicaSets kept at zero replicas (up to `revisionHistoryLimit`). The Deployment scales an old one back up.

### Q: What happens to a bare pod when its node dies?
**A:** Nothing replaces it. Only controllers (Deployments, StatefulSets, KubeVirt's VM controller...) create replacements.

### Q: Why do you need a Service instead of connecting to pod IPs?
**A:** Pod IPs change whenever pods are replaced. A Service gives a stable virtual IP, a DNS name, and load balancing across ready pods matched by labels.

### Q: What's the fully qualified DNS name of Service `db` in namespace `payments`?
**A:** `db.payments.svc.cluster.local`

### Q: Explain `port`, `targetPort` and `nodePort`.
**A:** `targetPort`: the port the container listens on. `port`: the Service's own port in the cluster. `nodePort`: a port (30000-32767) opened on every node for outside traffic.

### Q: A Service has no endpoints. Give two likely causes.
**A:** Its selector doesn't match the pod labels, or the matching pods aren't ready (failing readiness probes). A third possibility is that no pods exist at all.

### Q: What is the default behaviour when no NetworkPolicy exists? And what happens once a pod is selected by an ingress policy?
**A:** With no policy, all traffic is allowed. Once a pod is selected by an ingress policy, only the explicitly allowed ingress reaches it.

### Q: A cluster accepts your NetworkPolicy, but traffic isn't blocked. Why?
**A:** The CNI plugin doesn't enforce policies, or can't on this kernel. The API stores the objects regardless. Always test enforcement.

### Q: Does Kubernetes NetworkPolicy protect a Harvester VM on a VLAN network?
**A:** Not on the default bridge-based VLAN networks: that traffic goes straight to the physical network. VM micro-segmentation needs the Kube-OVN add-on (experimental in v1.9) or physical/VLAN controls.

### Q: What does Multus add to Kubernetes, and how does Harvester use it?
**A:** It lets a pod have multiple network interfaces (through NetworkAttachmentDefinitions). Harvester uses it to attach VM NICs to VLAN networks.

### Q: Why does a ResourceQuota on `requests.cpu` usually need a LimitRange?
**A:** With such a quota, pods that don't declare CPU requests are rejected. A LimitRange supplies default requests and limits.

### Q: Name four objects that are cluster-scoped (not namespaced).
**A:** Nodes, PersistentVolumes, StorageClasses, Namespaces, CRDs, ClusterRoles, ClusterRoleBindings (any four).

### Q: Is a Kubernetes Secret encrypted?
**A:** Not by default: it's base64-encoded. Protect Secrets with RBAC, encryption at rest (ideally KMS), mounting as files, and external secret managers.

### Q: Why prefer mounting a Secret as a file over an environment variable?
**A:** Env vars leak into child processes, crash dumps, debug output and `/proc/<pid>/environ`. Files can have tight permissions and are updated in place when the Secret changes.

### Q: A ConfigMap changes. Which consumers see it without a restart?
**A:** Volume-mounted files (after the kubelet sync delay, and not with `subPath`). Environment variables only change when the container restarts.

### Q: What does `CreateContainerConfigError` usually mean?
**A:** A referenced ConfigMap or Secret (or key) doesn't exist. Create it, and the kubelet retries automatically.

### Q: Map StorageClass, PVC and PV to Nutanix concepts.
**A:** StorageClass = storage container (with its policies). PVC = the request for a disk. PV = the actual vDisk.

### Q: Why did the PVC stay Pending until a pod used it?
**A:** The StorageClass uses `volumeBindingMode: WaitForFirstConsumer`, so provisioning waits until the scheduler picks a node (essential for node-local storage).

### Q: `reclaimPolicy: Delete` vs `Retain`: what happens to the data when the PVC is deleted?
**A:** Delete: the PV and its data are removed. Retain: the PV becomes `Released` and the data stays until an admin cleans it up.

### Q: Which access mode does KubeVirt live migration need, and why?
**A:** ReadWriteMany (RWX), because the source and target nodes access the disk at the same time during migration.

### Q: Which volumeMode do Harvester VM disks use?
**A:** Block. The guest OS puts its own filesystem on the raw device, as with a vDisk.

### Q: A PVC is Pending. List three things to check.
**A:** `describe pvc` events; whether the StorageClass exists (and is the default if none is named); WaitForFirstConsumer with no pod yet; whether the provisioner/CSI can meet the size or access mode; the provisioner's logs.

### Q: Name the three gates every API request passes through.
**A:** Authentication, authorization (RBAC), and admission control.

### Q: Role vs ClusterRole, and RoleBinding vs ClusterRoleBinding?
**A:** A Role holds namespaced rules; a ClusterRole holds cluster-wide, reusable rules. A RoleBinding grants a Role or ClusterRole within one namespace; a ClusterRoleBinding grants a ClusterRole everywhere.

### Q: RBAC has no deny rules. How do you take away a permission?
**A:** Remove or narrow the binding or rule that grants it. RBAC is purely additive with implicit deny.

### Q: Why is `create pods` in a namespace effectively a privileged permission?
**A:** A pod can mount any Secret and use any ServiceAccount in its namespace, so the creator can read those secrets and act as those identities.

### Q: The built-in ClusterRole `view` can read almost everything in a namespace. What can't it read, and why?
**A:** Secrets, because reading them would expose credentials and allow privilege escalation.

### Q: Why test an identity with `kubectl --kubeconfig=/dev/null --token=...` rather than just `--token=...`?
**A:** Otherwise kubectl also sends your admin client certificate from `~/.kube/config`. The API server authenticates the certificate first, so you're still admin.

### Q: What does the API server do with a custom resource when no controller exists for it?
**A:** It validates and stores it, and nothing else. Nothing happens until a controller acts on it.

### Q: What are the three steps of the reconcile loop?
**A:** Observe (desired and actual state), compare, act, and then repeat (and update status).

### Q: What is the status subresource for?
**A:** It gives `.status` its own endpoint, so controllers write status and users write spec without overwriting each other. RBAC can also treat the two separately.

### Q: What deletes a dependent object (like `db-01-vm`) when its owner is deleted?
**A:** The garbage collector, using the dependent's `ownerReferences`.

### Q: An object is stuck in `Terminating`. What do you check, and what is the risk of removing the finalizer?
**A:** Check `metadata.finalizers` and `deletionTimestamp`, then which controller owns the finalizer and why it isn't finishing. Removing it by hand skips that cleanup, which can orphan volumes, backups, IPs and so on.

### Q: Map lab t1-08's objects to KubeVirt.
**A:** VMRequest CRD → the `VirtualMachine` CRD. `controller.sh` → virt-controller (+ virt-handler). ConfigMap "VM" → VirtualMachineInstance + virt-launcher pod. `status.phase` → the VM's printableStatus/conditions.

### Q: What is an operator, compared with a controller?
**A:** An operator is a controller (or a set of them) that encodes the operational knowledge for one application: install, upgrade, back up, heal. Examples are virt-operator and the Longhorn manager.

### Q: Labels vs annotations?
**A:** Labels are for identifying and selecting objects (selectors, Services, `-l`). Annotations are non-selectable metadata, such as change causes, tool settings and ticket numbers.

### Q: Why run `kubectl diff -f file.yaml` before `kubectl apply`?
**A:** To review exactly what will change on the live object, like a change-review step. It catches drift and mistakes before they happen.

### Q: `kubectl get pods` shows "No resources found" but the app is running. Name two causes.
**A:** You're in the wrong namespace (the context's default namespace, or a missing `-n`), or the wrong context/cluster. Also check label or field selectors that filter too much.
