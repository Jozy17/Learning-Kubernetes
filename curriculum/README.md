# Curriculum

Study order. Each module links to its labs, and each has a flashcard quiz (`./labctl quiz <nn>`).

| # | Module | Labs | Status |
|---|---|---|---|
| 00 | [Orientation + Nutanix → Kubernetes/Harvester concept map](00-orientation-nutanix-map.md) | - | ✅ |
| 01 | [Containers: images, registries, runtimes](01-containers.md) | t1-01 | ✅ |
| 02 | [Kubernetes core](02-kubernetes-core/README.md) | t1-02 … t1-09 | ✅ |
| 03 | KubeVirt: VirtualMachine, VMI, DataVolumes | Tier 2 | planned |
| 04 | Harvester architecture: RKE2, KubeVirt, Longhorn, Multus/VLAN, images, backups, add-ons, Rancher | Tier 3 | planned |
| 05 | VMware for Nutanix admins: vCenter, datacenters, clusters, datastores, port groups/dvSwitches, VMware Tools, snapshots | Tier 4 prep | planned |
| 06 | Migration to Harvester with vm-import-controller | Tier 4 | planned |

**Target versions:** Kubernetes v1.36 in the labs, matching Harvester **v1.9.0**'s RKE2 v1.36.3.
All pins are in [`versions.env`](../versions.env).
