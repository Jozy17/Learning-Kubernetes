# Quiz 00 - Orientation and the Nutanix → Harvester map

Source: [curriculum/00-orientation-nutanix-map.md](../curriculum/00-orientation-nutanix-map.md).
Run with `./labctl quiz 00`. Format: each card is a `### Q:` heading followed by `**A:**`.

### Q: Harvester v1.9.0 is built on which Kubernetes distribution, and which Kubernetes minor version?
**A:** RKE2, v1.36 (v1.36.3+rke2r1).

### Q: Which component in Harvester plays the role of AHV (the hypervisor)?
**A:** KubeVirt. It runs each VM as KVM/QEMU inside a `virt-launcher` pod.

### Q: Which component in Harvester plays the role of Nutanix DSF (the distributed storage fabric)?
**A:** Longhorn (v1.12.1 in Harvester v1.9.0), a distributed block-storage system running inside the cluster.

### Q: What is the Harvester/Kubernetes equivalent of a Nutanix storage container?
**A:** A StorageClass. Harvester's default is `harvester-longhorn`, with 3 replicas.

### Q: What is the Harvester equivalent of a Nutanix vDisk?
**A:** A PVC (bound to a PV) in Block mode, backed by a Longhorn volume.

### Q: What is the Harvester equivalent of Nutanix RF2/RF3?
**A:** The Longhorn replica count (`numberOfReplicas`). The default StorageClass uses 3.

### Q: What is the Harvester equivalent of Prism Central, for managing many clusters?
**A:** Rancher, through its Virtualization Management feature, which imports multiple Harvester clusters.

### Q: What replaces Nutanix Guest Tools (NGT) in a Harvester VM?
**A:** `qemu-guest-agent`, for IP reporting, dynamic SSH key injection and clean shutdown. Windows VMs also need VirtIO drivers.

### Q: What is the Harvester equivalent of an AHV VM network with a VLAN ID?
**A:** A VM Network of type L2VlanNetwork on a cluster network. Under the hood it is a Multus NetworkAttachmentDefinition using a Linux bridge.

### Q: What does a Harvester "cluster network" correspond to in AHV terms?
**A:** The bridge and its uplink NIC bond on each node (br0/OVS + bond). `mgmt` is the built-in cluster network.

### Q: Where do Harvester VM backups go, and what types of storage are supported?
**A:** To a backup target, which is either an NFS server or S3-compatible storage.

### Q: Do VM snapshots in Harvester need a backup target?
**A:** No. Snapshots are local (stored with the Longhorn replicas). Backups need a backup target.

### Q: Harvester has no continuous async DR replication like Nutanix Protection Domains. How do you recover VMs on a second cluster?
**A:** Configure the same backup target on the second cluster. Backup metadata syncs across, and you restore the VMs there as new VMs.

### Q: What is the Harvester equivalent of Nutanix ADS / VMware DRS?
**A:** The virtual-machine-auto-balance add-on, based on the Kubernetes Descheduler. It is experimental in v1.9.0 and GA in v1.9.1.

### Q: Which Harvester add-on is the counterpart of Nutanix Move for this project?
**A:** vm-import-controller. It imports VMs from VMware (vCenter), OpenStack and OVA sources.

### Q: What is the Harvester equivalent of Nutanix Flow microsegmentation for VMs?
**A:** Nothing on the default VLAN (bridge) networks. The Kube-OVN add-on (experimental in v1.9) provides VM isolation using NetworkPolicies or security groups.

### Q: What are Nutanix "categories" called in Kubernetes?
**A:** Labels: key/value tags you can select on.

### Q: Name the three KubeVirt objects/things that exist for one running VM.
**A:** A `VirtualMachine` (the desired state), a `VirtualMachineInstance` (the running instance), and a `virt-launcher` pod (where QEMU actually runs).

### Q: What is the minimum RAM for a Harvester development/testing node, and why does that rule out nested Harvester on a 32 GB PC?
**A:** 32 GB for the Harvester node itself. A nested VM on a 32 GB host can only get part of that (roughly 20-24 GB), which is below the minimum.

### Q: Harvester v1.8.0+ supports new installs only in which boot mode?
**A:** UEFI. Legacy BIOS boot is deprecated for new installs.

### Q: What is the key mindset shift from Prism to Harvester/Kubernetes, in one phrase?
**A:** Declare desired state and let controllers reconcile it. Every VM, image and network is an object with a spec and a status.
