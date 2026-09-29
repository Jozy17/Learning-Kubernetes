# 00 - Orientation: from Nutanix to Kubernetes and Harvester

**Quiz:** `./labctl quiz 00` · **Reading time:** ~30 min

**Target:** SUSE Virtualization (Harvester) **v1.9.0**, whose bundled components are listed in
[`versions.env`](../versions.env). Where Harvester versions differ, the curriculum says so.

## 1. The big picture: what Harvester actually is
You already know HCI: compute and storage on the same nodes, managed as one cluster. Harvester is
HCI too, but every layer is built from **Kubernetes components**:

```
┌──────────────────────── Harvester node (bare metal) ────────────────────────┐
│  SUSE Linux Micro (immutable OS)                                             │
│  └─ RKE2 (Kubernetes v1.36 in Harvester v1.9.0)                              │
│      ├─ containerd                     ← runs every component as a pod       │
│      ├─ KubeVirt 1.8 + CDI             ← VMs as Kubernetes objects (KVM/QEMU)│
│      ├─ Longhorn 1.12                  ← distributed block storage (VM disks)│
│      ├─ Multus + bridge CNI + Harvester network controller ← VLAN VM networks│
│      ├─ Canal (Calico + Flannel)       ← pod network                          │
│      ├─ Harvester controllers + UI     ← images, backups, upgrades, settings │
│      └─ embedded Rancher               ← UI/auth plumbing (cattle-system)    │
└──────────────────────────────────────────────────────────────────────────────┘
```

So the learning path is:
1. **containers** (01)
2. **Kubernetes** (02)
3. **KubeVirt** (03), how VMs become Kubernetes objects
4. **Harvester** (04), how it all fits together as HCI
5. **VMware** (05), enough to read your source environment
6. **Migration** (06)

## 2. Concept map: Nutanix → Kubernetes → Harvester (→ VMware)
Keep this table open while you study. The VMware column is a preview for module 05, so you can
start recognising the terms in your source environment.

### Management and compute
| Nutanix | Plain Kubernetes | Harvester | VMware (preview) |
|---|---|---|---|
| **Prism Element** (per-cluster UI + API) | kube-apiserver + `kubectl` | Harvester UI + Kubernetes API of that cluster | vCenter / host client |
| **Prism Central** (multi-cluster) | none built in | **Rancher** → *Virtualization Management* (imports many Harvester clusters) | vCenter (Enhanced Linked Mode) |
| **AHV** (KVM-based hypervisor) | container runtime (containerd) for pods | **KubeVirt**: KVM/QEMU running inside `virt-launcher` pods | ESXi |
| **CVM / Acropolis services** | control plane + controllers | RKE2 control plane + KubeVirt/Longhorn/Harvester controllers (no separate CVM) | vCenter services, hostd |
| Node / host | Node | Harvester node (management, worker or **witness** role) | ESXi host |
| Cluster (3+ nodes) | Cluster | Harvester cluster: 3 management nodes for HA; single-node clusters exist but without HA | vSphere cluster |
| VM | (pod, for containers) | `VirtualMachine` → `VirtualMachineInstance` → `virt-launcher` pod | VM |
| **NGT** (Nutanix Guest Tools) | n/a | `qemu-guest-agent` (IP reporting, SSH key injection, clean shutdown) | VMware Tools |
| Nutanix VirtIO drivers (Windows) | n/a | **VirtIO drivers**: the same idea, and needed for Windows guests | PVSCSI / vmxnet3 drivers |
| VM HA (restart on host failure) | controllers recreate pods | KubeVirt restarts VMs per their `runStrategy` | vSphere HA |
| Live migration | n/a (pods are replaced) | KubeVirt **live migration** | vMotion |
| ADS (dynamic scheduling) | scheduler + Descheduler | **VM auto-balance add-on** (Descheduler; experimental in v1.9.0, GA in v1.9.1) | DRS |
| Host maintenance mode | `kubectl drain` / `cordon` | Harvester **Maintenance Mode** (live-migrates VMs off; needs ≥2 active nodes) | ESXi maintenance mode |
| Affinity / anti-affinity policies | node/pod affinity, taints | VM scheduling rules (node selectors, affinity) | DRS rules |
| GPU / PCI passthrough | device plugins | PCI devices add-on, vGPU support | DirectPath I/O, vGPU |
| LCM (one-click upgrades) | n/a | Harvester upgrade (ISO-based, rolling, node by node) | vLCM |
| Karbon / NKE (Kubernetes on Nutanix) | n/a | **Guest clusters**: Rancher provisions RKE2/K3s clusters on Harvester VMs | Tanzu (vSphere Kubernetes) |

### Storage
| Nutanix | Plain Kubernetes | Harvester | VMware (preview) |
|---|---|---|---|
| **DSF** (distributed storage fabric) | CSI driver | **Longhorn** | vSAN / VMFS |
| **Storage container** | **StorageClass** | `harvester-longhorn` (default) + custom StorageClasses | Datastore + storage policy |
| **RF2 / RF3** | n/a | Longhorn `numberOfReplicas` (default **3**) | vSAN FTT |
| **vDisk** | **PV** (bound via **PVC**) | VM volume = PVC in **Block** mode on Longhorn | VMDK |
| Volume Group | PVC (block) | Hot-plug volume | RDM / shared VMDK |
| Data locality | n/a | Longhorn data-locality setting | n/a |
| **Image Service** | (container registries, for containers) | **VM Images** (`VirtualMachineImage`: from URL, upload, or volume) | Content Library / templates |

### Networking
| Nutanix | Plain Kubernetes | Harvester | VMware (preview) |
|---|---|---|---|
| br0 / OVS bridge + NIC bond | CNI plugin (pod network) | **Cluster network** (a bond of uplink NICs on each node); built-in `mgmt` | vSwitch / **dvSwitch** + uplinks |
| VM network (VLAN ID) | n/a (one pod network) | **VM Network** of type L2VlanNetwork (also untagged and VLAN trunk) = a `NetworkAttachmentDefinition` via **Multus** | **Port group** (VLAN ID) |
| IPAM | pod CIDR, Service IPs | Managed DHCP add-on; IP pools for load balancers | n/a |
| Flow microsegmentation | **NetworkPolicy** | NetworkPolicy for pods; for VMs, the **Kube-OVN add-on** (experimental) | NSX distributed firewall |
| Load balancer (external) | Service `LoadBalancer` | Harvester load balancer + IP pools | NSX / Avi LB |

### Data protection and migration
| Nutanix | Plain Kubernetes | Harvester | VMware (preview) |
|---|---|---|---|
| Local snapshots | VolumeSnapshot | **VM snapshots**; no backup target needed | VM snapshots (delta VMDKs) |
| Protection Domains → backup | n/a | **VM backups** to a **backup target** (NFS or S3); restore as a new VM or replace an existing one | Backup via VADP (e.g. Veeam) |
| Async DR to a second site | n/a | No continuous replication. Restore a backup on **another cluster** that uses the same backup target | vSphere Replication / SRM |
| **Nutanix Move** | n/a | **vm-import-controller** add-on (sources: VMware, OpenStack, OVA) | (source environment) |

### Governance and security
| Nutanix | Plain Kubernetes | Harvester |
|---|---|---|
| Categories | **Labels** | Labels |
| Projects (Prism Central) | **Namespaces** + ResourceQuota | Namespaces, grouped into Rancher **Projects** |
| Roles (Viewer / Operator / Admin) | ClusterRoles `view` / `edit` / `admin` via RBAC | Rancher and Harvester RBAC |
| AD authentication | OIDC / certificates / tokens | Rancher auth providers (AD, LDAP, SAML, OIDC) |
| Guest customisation (Sysprep / cloud-init) | ConfigMaps / Secrets | **cloud-init** user data stored in **Secrets** |

## 3. Mindset shifts
1. **Declare, don't click.** Everything in Harvester is a Kubernetes object with a `spec`. The UI
   just writes YAML for you. You can `kubectl get vm -A`, back up YAML, and put it in git.
2. **Controllers do the work.** When something is "stuck", a controller is failing to reconcile.
   Learn to find the controller, its logs, the object's events, and its finalizers (lab t1-08).
3. **Namespaces matter.** VMs, images and networks live in namespaces, and so do the Secrets and
   RBAC around them.
4. **Storage replication is software you can see.** Longhorn replicas, engines and instance
   managers are pods and custom resources you can inspect.
5. **Two networks.** The pod network for the platform itself, and VLAN VM networks for your
   workloads. They follow different rules.

## 4. How to study with this repo
1. Read the module.
2. Do the lab: `./labctl start <lab>` → the README tasks → `./labctl verify <lab>`.
3. Do the break/fix: `./labctl breakfix <lab>` → diagnose → `./labctl breakfix <lab> --check`.
4. Answer the lab's review questions out loud or in your notes.
5. Run the quiz: `./labctl quiz <module>`, later `--missed` for spaced review.
6. `./labctl progress` shows where you are.

## Official docs
- Harvester v1.9 docs home - <https://docs.harvesterhci.io/v1.9/>
- Harvester glossary - <https://docs.harvesterhci.io/v1.9/getting-started/glossary>
- Hardware and network requirements - <https://docs.harvesterhci.io/v1.9/install/requirements>
- Rancher integration - <https://docs.harvesterhci.io/v1.9/rancher/rancher-integration>
- KubeVirt user guide - <https://kubevirt.io/user-guide/>
- Longhorn v1.12.1 docs - <https://longhorn.io/docs/1.12.1/>
- Kubernetes concepts - <https://kubernetes.io/docs/concepts/>
