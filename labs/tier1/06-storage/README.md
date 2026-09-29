# Lab t1-06: Storage: PV, PVC and StorageClass

**Curriculum:** [02e - Storage](../../../curriculum/02-kubernetes-core/02e-storage.md) · **Time:** ~60 min

## Objectives
1. Explain the **PV / PVC / StorageClass** model and who creates each object.
2. Provision storage dynamically, and explain `WaitForFirstConsumer`.
3. Prove that data outlives a pod.
4. Provision a PV statically, and see what **reclaim policies** do.
5. Troubleshoot a PVC that stays `Pending`.

> **Nutanix mapping**
>
> This mapping carries straight over to Harvester, where every VM disk is a PVC.
>
> | Kubernetes | Nutanix | Notes |
> |---|---|---|
> | **StorageClass** | **Storage container** (with its RF / compression / dedup settings) | A named "type of storage" with a provisioner and parameters |
> | **PersistentVolumeClaim (PVC)** | "I need a 1 GiB disk", the request in a VM's disk config | Namespaced; made by the app owner |
> | **PersistentVolume (PV)** | The actual **vDisk** | Cluster-scoped; usually created by the provisioner |
> | Dynamic provisioning | Prism creating the vDisk when you add a disk to a VM | Happens automatically for every PVC |
> | `ReadWriteOnce` | vDisk attached to one VM | `ReadWriteMany` is closer to a Nutanix Files share |
> | Provisioner (CSI driver) | Stargate / DSF doing the I/O | In Harvester this is **Longhorn** |
>
> **Important difference:** kind's `local-path` provisioner keeps data on **one node's local
> disk, with no replication**. It's like a single disk with no RF. Longhorn in Harvester keeps
> replicas on several nodes (the default is 3), which is much closer to Nutanix RF2/RF3.

## Based on (official docs)
- Persistent Volumes - <https://kubernetes.io/docs/concepts/storage/persistent-volumes/>
- Storage Classes - <https://kubernetes.io/docs/concepts/storage/storage-classes/>
- Dynamic provisioning - <https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/>
- Configure a Pod to use a PV (tutorial) - <https://kubernetes.io/docs/tutorials/configuration/configure-persistent-volume-storage/>
- Rancher local-path-provisioner (what kind uses) - <https://github.com/rancher/local-path-provisioner>

## Setup
```bash
./labctl start t1-06
```

---

## Tasks

### Task 1 - Look at the StorageClass
```bash
kubectl get storageclass
kubectl get storageclass standard -o yaml
```
Find these four things:
- `provisioner: rancher.io/local-path` is the driver that creates the volumes.
- `reclaimPolicy: Delete` means the PV and its data are deleted when the PVC is deleted.
- `volumeBindingMode: WaitForFirstConsumer` means the volume isn't created until a pod uses it.
- The annotation `is-default-class: "true"` means PVCs that name no class get this one.

### Task 2 - Request storage (PVC)
`work/data-pvc.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: lab-storage
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
```
```bash
kubectl apply -f labs/tier1/06-storage/work/data-pvc.yaml
kubectl -n lab-storage get pvc                       # STATUS: Pending - expected!
kubectl -n lab-storage describe pvc data-pvc | tail -3   # "waiting for first consumer"
```
**Why Pending is correct here:** with local disks, the volume must be created on the node where
the pod will run. The scheduler hasn't picked a node yet, so provisioning waits.

### Task 3 - A pod writes data
`work/writer.yaml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: lab-storage
spec:
  containers:
  - name: writer
    image: busybox:1.37
    command: ["sh", "-c", "echo \"written by writer on $(date)\" > /data/proof.txt; sleep infinity"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```
```bash
kubectl apply -f labs/tier1/06-storage/work/writer.yaml
kubectl -n lab-storage get pvc,pv          # now Bound, and a PV named pvc-<uid> appeared
kubectl -n lab-storage exec writer -- cat /data/proof.txt
kubectl get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.name,PATH:.spec.hostPath.path,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
```
The PV is pinned to one node through `nodeAffinity`, because that's where the data physically
lives.

### Task 4 - Data outlives the pod
```bash
kubectl -n lab-storage delete pod writer
kubectl -n lab-storage get pvc               # still Bound - the claim and data remain
```
Create `work/reader.yaml`. Copy `writer.yaml`, change the name to `reader`, and change the
command to `["sleep", "infinity"]`. Then:
```bash
kubectl apply -f labs/tier1/06-storage/work/reader.yaml
kubectl -n lab-storage exec reader -- cat /data/proof.txt      # "written by writer ..."
kubectl -n lab-storage get pod reader -o wide                   # same node as the PV
```
The scheduler placed `reader` on the PV's node automatically. With Longhorn, volumes can attach
on any node, which is what makes VM **live migration** possible in Harvester.

### Task 5 - Static provisioning and reclaim policy
Sometimes an admin creates the PV by hand, for example to present existing storage. Write
`work/static.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-pv                     # cluster-scoped: no namespace
spec:
  capacity:
    storage: 500Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain   # keep the data when the claim is deleted
  storageClassName: manual                # a made-up class name used only for matching
  hostPath:                               # LAB ONLY - never use hostPath for real data
    path: /tmp/lab-static-pv
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-pvc
  namespace: lab-storage
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual               # must match the PV's class to bind
  resources:
    requests:
      storage: 500Mi
```
```bash
kubectl apply -f labs/tier1/06-storage/work/static.yaml
kubectl get pv static-pv                     # Bound to lab-storage/static-pvc (no pod needed: no WFFC here)
```
> **Retain vs Delete.** Imagine `static-pvc` deleted by mistake. With `Retain`, the PV moves to
> `Released` and the data stays until an admin cleans it up. With `Delete`, the data is gone.
> Harvester VM disks use Longhorn StorageClasses, so check their reclaim policy before you delete
> things. Try it *after* you verify, if you like:
> `kubectl -n lab-storage delete pvc static-pvc; kubectl get pv static-pv`, then
> `./labctl reset t1-06` to start clean.

## Check your work
```bash
./labctl verify t1-06
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-06
```
The `db` pod is stuck `Pending` after its manifests were copied from another cluster.

<details><summary>Hint 1</summary>

`kubectl -n lab-storage describe pod -l app=db`: the scheduler complains about an unbound PVC.
Now `describe pvc db-data`. What StorageClass does it ask for, and does that class exist
(`kubectl get sc`)?
</details>

<details><summary>Hint 2</summary>

There are two valid fixes:
- **(a)** Delete and recreate the PVC with `storageClassName: standard`. The PVC's class is
  immutable, so you can't just edit it.
- **(b)** Create a StorageClass named `fast-ssd` that uses the `rancher.io/local-path`
  provisioner.

Which fix would you choose in production, and why? Option (b) is how you'd map classes during a
**migration**, which is a theme in Tier 4.
</details>

<details><summary>Hint 3</summary>

For (a):
```bash
kubectl -n lab-storage get pvc db-data -o yaml > labs/tier1/06-storage/work/db-pvc.yaml
# edit: storageClassName: standard ; delete status, uid, resourceVersion, creationTimestamp, annotations
kubectl -n lab-storage delete pvc db-data && kubectl apply -f labs/tier1/06-storage/work/db-pvc.yaml
```
The Pending pod picks up the new claim by itself.
</details>

Check: `./labctl breakfix t1-06 --check`

## Cleanup
```bash
./labctl cleanup t1-06
```
This also deletes `static-pv` and a `fast-ssd` StorageClass if you created one. Both are
cluster-scoped, so deleting the namespace doesn't remove them.

## Review questions
1. Which of PV, PVC and StorageClass are namespaced, and which are cluster-wide? Why does that
   split make sense?
2. What does `WaitForFirstConsumer` solve? When would `Immediate` binding be a problem?
3. What happens to the data when you delete a PVC whose PV has `reclaimPolicy: Delete`? And with
   `Retain`?
4. Why did `reader` land on the same node as `writer`? Would that happen with Longhorn?
5. Map StorageClass, PVC and PV to Nutanix concepts.
6. A PVC is `Pending`. List three possible causes.
7. Why is `local-path` (no replication) unsuitable for production VMs?
