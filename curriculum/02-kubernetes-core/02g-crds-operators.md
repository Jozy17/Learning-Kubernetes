# 02g - CRDs, controllers and operators

**Lab:** [t1-08](../../labs/tier1/08-crds-operators/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~25 min

**Why this is the bridge to everything else:** KubeVirt, Longhorn, Harvester, Rancher and
vm-import-controller are all *CRDs + controllers*. When you run `kubectl get vm` on Harvester,
you're listing custom resources that a controller turns into running QEMU processes.

## 1. Extending the API
A **CustomResourceDefinition** (CRD) teaches the API server a new `kind`. After you apply a CRD:
- kubectl, RBAC, `explain`, watch, labels and namespaces all work for the new kind
  automatically
- objects are validated against the CRD's **OpenAPI v3 schema** (types, required fields,
  min/max values, defaults)
- the **status subresource** separates user-owned `.spec` from controller-owned `.status`
- **printer columns** control what `kubectl get` shows

The API server only **stores and validates** custom resources. Nothing happens until a controller
acts on them.

## 2. Controllers: the reconcile loop
```
        ┌────────────── watch ──────────────┐
        ▼                                   │
  observe desired (spec) ─▶ compare with actual ─▶ act (create/update/delete)
        ▲                                   │
        └──────── update .status ◀──────────┘
```
Properties of good controllers:
- **Level-triggered and idempotent.** They react to the current state, not to a sequence of
  events. If a change is missed, the next pass fixes it (lab t1-08 Task 6: the deleted
  ConfigMap came back).
- **Own what they create**, through `ownerReferences`, so the **garbage collector** removes
  dependents when the owner is deleted (lab t1-08 Task 7).
- **Use finalizers** when they must do external cleanup before an object disappears, for
  example detaching a Longhorn volume or deleting a backup.

## 3. Finalizers and stuck deletions
Deleting an object that has `metadata.finalizers` only sets `deletionTimestamp`. The object stays
until every finalizer has been removed by the controller that added it. If that controller is
broken, uninstalled or blocked, the object hangs in `Terminating`, and so does its namespace.

Safe triage:
1. `kubectl get <obj> -o yaml`: which finalizers are set?
2. Which controller owns them? Is it running, and what do its logs say?
3. Fix the controller, or the reason it's blocked, if you can.
4. Only as a last resort, remove the finalizer by hand, and accept that its cleanup is skipped
   (orphaned volumes, IPs, backups...).

## 4. Operators
An **operator** is a controller (or a set of them) that encodes a human operator's knowledge
for one application: install, configure, upgrade, back up, heal. Examples you'll meet:

| Operator / controller | Custom resources it reconciles |
|---|---|
| **virt-operator** (KubeVirt) | `KubeVirt`: installs and upgrades KubeVirt itself |
| **virt-controller** (KubeVirt) | `VirtualMachine` → `VirtualMachineInstance` → virt-launcher pod |
| **CDI** (Containerized Data Importer) | `DataVolume`: imports and clones disk images into PVCs |
| **Longhorn manager** | `volumes.longhorn.io`, replicas, engines, backups |
| **Harvester controllers** | VM images, backups, restores, networks, upgrades... |
| **vm-import-controller** | `VmwareSource`, `OvaSource`, `VirtualMachineImport` → a Harvester VM (Tier 4) |

## 5. Mapping lab t1-08 to KubeVirt
| Lab t1-08 | KubeVirt / Harvester |
|---|---|
| CRD `vmrequests.lab.example.com` | CRD `virtualmachines.kubevirt.io` |
| `VMRequest web-01` (spec: cpu, memory, image) | `VirtualMachine` (spec: CPU, memory, disks, networks, `runStrategy`) |
| `controller.sh` | `virt-controller` (+ `virt-handler` on each node) |
| ConfigMap `web-01-vm` (owned) | `VirtualMachineInstance` + `virt-launcher` pod (owned) |
| `status.phase: Provisioned` | `status.printableStatus: Running`, conditions |
| Finalizer `disk-cleanup` | Finalizers on VMs, PVCs and images |

## Official docs
- Custom resources - <https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/>
- CRDs (task) - <https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/>
- Controllers - <https://kubernetes.io/docs/concepts/architecture/controller/>
- Operator pattern - <https://kubernetes.io/docs/concepts/extend-kubernetes/operator/>
- Owners and dependents - <https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/>
- Garbage collection - <https://kubernetes.io/docs/concepts/architecture/garbage-collection/>
- Finalizers - <https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/>

## Key terms
CRD · custom resource · OpenAPI schema · status subresource · printer columns · controller ·
reconcile · level-triggered · idempotent · ownerReference · garbage collection · finalizer ·
operator
