# Lab t1-08: CRDs, controllers and operators

**Curriculum:** [02g - CRDs & Operators](../../../curriculum/02-kubernetes-core/02g-crds-operators.md) · **Time:** ~75 min

**This is the most important lab in Tier 1.** KubeVirt and Harvester are built from CRDs and
controllers. A KubeVirt `VirtualMachine` is a custom resource, and a Harvester VM image, VM
backup or `VirtualMachineImport` is one too. Once you've built a small one yourself, the rest of
the course stops being magic.

## Objectives
1. Extend the Kubernetes API with a **CustomResourceDefinition** (CRD) that includes a
   validation schema.
2. Create, list and `explain` your own custom resources like built-in ones.
3. Run a **controller** and watch it reconcile desired state into actual state.
4. Understand **ownerReferences** and garbage collection.
5. Understand **finalizers**, including why objects get stuck in `Terminating` and how to fix
   that safely.

> **Nutanix mapping**
> - A **CRD** is like adding a brand-new entity type to Prism's API, say "VM request", that
>   `kubectl`, RBAC and the API server immediately understand. Nutanix can't do that; Kubernetes
>   is built for it.
> - A **controller** is like the Acropolis leader that constantly checks "should VM X be running,
>   and is it?", and fixes any difference.
> - An **operator** is a controller that holds operational knowledge (install, upgrade, backup)
>   for one piece of software. KubeVirt's `virt-operator` installs and upgrades KubeVirt itself,
>   and Longhorn has its own manager.

## Based on (official docs)
- Custom Resources - <https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/>
- Extend the API with CRDs (task) - <https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/>
- Controllers - <https://kubernetes.io/docs/concepts/architecture/controller/>
- Operator pattern - <https://kubernetes.io/docs/concepts/extend-kubernetes/operator/>
- Owners and dependents - <https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/>
- Finalizers - <https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/>

## Setup
```bash
./labctl start t1-08
```

---

## Tasks

### Task 1 - The API is extensible
```bash
kubectl api-resources | head -20          # every kind of object the API server knows
kubectl api-resources | wc -l
kubectl get crd                           # kind ships almost none; a Harvester cluster has many dozens
```

### Task 2 - Define a new resource type: VMRequest
Write `work/vmrequest-crd.yaml`. It's long, but every block matters, and a real KubeVirt CRD has
the same structure:
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: vmrequests.lab.example.com       # must be <plural>.<group>
spec:
  group: lab.example.com                 # API group (KubeVirt uses kubevirt.io)
  scope: Namespaced
  names:
    kind: VMRequest
    plural: vmrequests
    singular: vmrequest
    shortNames: [vmr]
  versions:
  - name: v1alpha1
    served: true                         # the API server answers for this version
    storage: true                        # objects are stored in etcd as this version
    subresources:
      status: {}                         # .status gets its own endpoint (only controllers write it)
    additionalPrinterColumns:            # what "kubectl get vmr" shows
    - {name: CPU,    type: integer, jsonPath: .spec.cpu}
    - {name: MemGi,  type: integer, jsonPath: .spec.memoryGi}
    - {name: Image,  type: string,  jsonPath: .spec.image}
    - {name: Phase,  type: string,  jsonPath: .status.phase}
    - {name: Age,    type: date,    jsonPath: .metadata.creationTimestamp}
    schema:
      openAPIV3Schema:                   # validation - the API rejects bad objects up front
        type: object
        properties:
          spec:
            type: object
            required: [cpu, memoryGi, image]
            properties:
              cpu:      {type: integer, minimum: 1, maximum: 16, description: "vCPUs"}
              memoryGi: {type: integer, minimum: 1, maximum: 128, description: "Memory in GiB"}
              image:    {type: string, description: "Name of the VM image to boot"}
              network:  {type: string, default: "default", description: "Network to attach"}
          status:
            type: object
            properties:
              phase:   {type: string}
              message: {type: string}
```
```bash
kubectl apply -f labs/tier1/08-crds-operators/work/vmrequest-crd.yaml
kubectl get crd vmrequests.lab.example.com
kubectl api-resources --api-group=lab.example.com
kubectl explain vmrequest.spec                # docs generated from YOUR schema
```
If `explain` says it "couldn't find resource", wait a few seconds and try again. kubectl caches
the list of API types and refreshes it shortly after a new CRD appears.

### Task 3 - Create custom resources
`work/vmrequests.yaml`:
```yaml
apiVersion: lab.example.com/v1alpha1
kind: VMRequest
metadata:
  name: web-01
  namespace: lab-crd
spec:
  cpu: 2
  memoryGi: 4
  image: ubuntu-24.04
---
apiVersion: lab.example.com/v1alpha1
kind: VMRequest
metadata:
  name: db-01
  namespace: lab-crd
spec:
  cpu: 4
  memoryGi: 16
  image: rocky-9
  network: vlan-100
```
```bash
kubectl apply -f labs/tier1/08-crds-operators/work/vmrequests.yaml
kubectl -n lab-crd get vmr                     # your printer columns; Phase is empty - nobody acted yet
kubectl -n lab-crd get vmr web-01 -o yaml      # note: network was defaulted to "default"
```
**Key insight:** the API server *stored* your objects, and that's all it did. Nothing happens
until a **controller** acts on them.

### Task 4 - Validation in action
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: lab.example.com/v1alpha1
kind: VMRequest
metadata: {name: monster, namespace: lab-crd}
spec: {cpu: 64, memoryGi: 4, image: ubuntu-24.04}
EOF
```
The API server rejects it, because 64 is more than the maximum of 16. Bad input is refused
before any controller ever sees it.

### Task 5 - Run the controller
Read [`controller.sh`](controller.sh) first. It's short, and the comments explain each step.
Then run it in a **second terminal**:
```bash
labs/tier1/08-crds-operators/controller.sh
```
Back in the first terminal:
```bash
kubectl -n lab-crd get vmr                      # Phase: Provisioned
kubectl -n lab-crd get configmaps -l app.kubernetes.io/managed-by=vmrequest-controller
kubectl -n lab-crd get configmap web-01-vm -o yaml | grep -A6 ownerReferences
```

### Task 6 - Reconciliation fixes drift
Keep the controller running.
```bash
kubectl -n lab-crd delete configmap web-01-vm      # someone deletes the "VM" by hand...
kubectl -n lab-crd get configmap web-01-vm         # ...a few seconds later it's back
kubectl -n lab-crd patch vmr web-01 --type=merge -p '{"spec":{"memoryGi":8}}'   # change desired state
kubectl -n lab-crd get configmap web-01-vm -o jsonpath='{.data.memoryGi}{"\n"}' # -> 8
```
The controller doesn't care *why* reality differs from the spec; it just converges. KubeVirt
does the same when a VM's pod disappears: the `VirtualMachine` says "running", so it starts a
new one.

### Task 7 - Garbage collection through ownerReferences
```bash
kubectl -n lab-crd delete vmr db-01
kubectl -n lab-crd get configmap db-01-vm        # NotFound within a few seconds - the garbage collector removed it
```
The controller never deleted anything. The ownerReference told Kubernetes that `db-01-vm`
belongs to `db-01`. KubeVirt uses the same mechanism: delete a `VirtualMachine` and its VMI and
pod go too.

## Check your work
```bash
./labctl verify t1-08
```

---

## Break/fix scenario: the stuck object
```bash
./labctl breakfix t1-08
```
`legacy-01` was deleted but won't go away. This is one of the most common real-world
Kubernetes problems. It shows up as stuck namespaces, stuck PVCs, and, in Harvester, stuck VMs
or images when a controller isn't doing its job.

<details><summary>Hint 1</summary>

`kubectl -n lab-crd get vmr legacy-01 -o yaml`. Look at `metadata.deletionTimestamp` (set, so
deletion was requested) and `metadata.finalizers`, which is not empty.
</details>

<details><summary>Hint 2</summary>

A **finalizer** is a "don't delete me until controller X has cleaned up" marker. The API server
waits until the list is empty. The controller responsible, `disk-cleanup`, no longer exists, so
nobody will ever remove its entry.
</details>

<details><summary>Hint 3</summary>

```bash
kubectl -n lab-crd patch vmr legacy-01 --type=merge -p '{"metadata":{"finalizers":null}}'
```
**Be careful with this in real life.** Removing a finalizer skips the cleanup it protected,
which could leave orphaned Longhorn volumes, backups or load balancer IPs. First find out which
controller owns the finalizer and why it isn't finishing. Only strip it by hand when you're sure
the cleanup is done or unnecessary, as the ticket says here.
</details>

Check: `./labctl breakfix t1-08 --check`

## Cleanup
Stop `controller.sh` (Ctrl+C), then:
```bash
./labctl cleanup t1-08
```

## Review questions
1. What does the API server do with a custom resource when no controller exists for it?
2. What's the purpose of the `status` subresource? Why shouldn't users write `.status`?
3. Describe the reconcile loop in three verbs.
4. What deleted `db-01-vm`, and what information did it use?
5. An object is stuck in `Terminating`. What do you check, and what are the risks of removing a
   finalizer by hand?
6. How do the objects in this lab map to KubeVirt? (VMRequest → ?, controller → ?,
   ConfigMap "VM" → ?)
7. What's the difference between a controller and an operator?
