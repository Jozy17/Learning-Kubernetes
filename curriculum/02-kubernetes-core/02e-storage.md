# 02e - Storage: PV, PVC and StorageClass

**Lab:** [t1-06](../../labs/tier1/06-storage/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~30 min

This module matters more to you than most. **In Harvester, every VM disk is a PVC**, backed by a
Longhorn volume. Understanding PVCs means understanding VM disks, images, snapshots, backups and
migration imports.

## 1. Volumes, from temporary to persistent
| Kind | Lifetime | Example |
|---|---|---|
| Container writable layer | Dies with the container | Temp files |
| `emptyDir` | Dies with the pod | Scratch space shared by containers (lab t1-02) |
| `configMap` / `secret` volumes | Follow the object | Config files (lab t1-05) |
| **PersistentVolumeClaim** | **Independent of any pod** | Databases, **VM disks** |

## 2. The three storage objects
```
  App team                           Cluster / storage admin
  ────────                           ───────────────────────
  PVC  "I need 10Gi, RWO,     ─bind─▶  PV  "10Gi volume on backend X"
        class=fast"                    ▲
                                       │ created on demand by
                          StorageClass "fast": provisioner + parameters
                                       (the CSI driver, e.g. Longhorn)
```
| Object | Scope | Created by | Nutanix analogy |
|---|---|---|---|
| **StorageClass** | Cluster | Admin | **Storage container**, with its policies (RF, compression...) |
| **PersistentVolumeClaim** | Namespace | App owner / VM creator | "Add a 10 GiB disk to this VM" |
| **PersistentVolume** | Cluster | Usually the provisioner, automatically | The **vDisk** itself |

**Dynamic provisioning:** when you create a PVC that names a StorageClass, that class's
provisioner creates a matching PV, and the PVC **binds** to it one-to-one.

## 3. Key settings
- **accessModes**
  - `ReadWriteOnce` (RWO): mounted read-write by one node
  - `ReadOnlyMany` (ROX)
  - `ReadWriteMany` (RWX): read-write from many nodes. KubeVirt live migration needs this,
    because source and target nodes use the disk at the same moment.
  - `ReadWriteOncePod`: a single pod only
- **volumeMode**: `Filesystem` (the default; mounted as a directory) or `Block` (presented as a
  raw block device). **VM disks in Harvester use Block mode**, because the guest OS brings its
  own filesystem, just as with a vDisk.
- **reclaimPolicy**: `Delete` (the default for dynamic PVs; data goes with the PVC) or `Retain`
  (the PV and data stay behind for an admin to deal with).
- **volumeBindingMode**: `Immediate` or `WaitForFirstConsumer`. WFFC delays provisioning until a
  pod is scheduled, which is essential for node-local storage.
- **allowVolumeExpansion**: whether PVCs of that class can be grown (like extending a vDisk).

## 4. CSI: how storage vendors plug in
The **Container Storage Interface** is the standard plugin API (like VAAI/VASA for vSphere, or
how Nutanix exposes Volumes). A CSI driver provides provisioning, attach/detach, mount,
**snapshots** (`VolumeSnapshot` objects), **clones** and **expansion**.

## 5. Longhorn in Harvester (preview of Tier 3)
Harvester v1.9.0 bundles Longhorn **v1.12.1**.

Longhorn is a CNCF distributed block-storage system that runs *inside* the cluster:
- Each volume has an **engine** and **replicas** placed on different nodes. Harvester's default
  StorageClass `harvester-longhorn` uses **3 replicas**, which is conceptually close to Nutanix **RF3**, and you can
  create classes with 2.
- Replicas are rebuilt automatically when a node or disk fails, like Curator/Stargate
  re-replication.
- Volume **snapshots** are stored locally with the replicas. **Backups** are copied to an
  external **backup target** (NFS or S3). In Nutanix terms that's like the difference between
  local snapshots and replicating to another site or an object store.
- **Data locality** is a setting (it tries to keep a replica on the node running the workload),
  similar to Nutanix data locality, but it isn't automatic by default.

The key difference from lab t1-06: kind's `local-path` provisioner has **no replication**, so
losing the node means losing the data.

## 6. Troubleshooting a Pending PVC
1. `kubectl describe pvc X`: read the Events.
2. Does the StorageClass exist? Is it the default? (`kubectl get sc`)
3. With WFFC, is there a pod using the PVC yet?
4. Can the provisioner satisfy the request (size, access mode, available capacity)?
5. Look at the provisioner/CSI pods' logs (`longhorn-system` in Harvester).

## Official docs
- Volumes - <https://kubernetes.io/docs/concepts/storage/volumes/>
- Persistent Volumes - <https://kubernetes.io/docs/concepts/storage/persistent-volumes/>
- Storage Classes - <https://kubernetes.io/docs/concepts/storage/storage-classes/>
- Dynamic provisioning - <https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/>
- Volume snapshots - <https://kubernetes.io/docs/concepts/storage/volume-snapshots/>
- Longhorn concepts (v1.12.1, the version in Harvester v1.9.0) - <https://longhorn.io/docs/1.12.1/concepts/>

## Key terms
PV · PVC · StorageClass · provisioner · CSI · bind · access modes (RWO/RWX) · volumeMode Block ·
reclaimPolicy · WaitForFirstConsumer · VolumeSnapshot · Longhorn replica · backup target
