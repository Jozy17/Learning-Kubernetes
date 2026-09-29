# Tier 1 - Kubernetes fundamentals (kind)

Runs on a 3-node **kind** cluster (`./labctl cluster up`) with Kubernetes **v1.36.4**, the same
minor version as Harvester v1.9.0's RKE2. It uses about 2-3 GB RAM.

| Lab | Topic | Curriculum | Break/fix you'll solve |
|---|---|---|---|
| [t1-01](01-containers/README.md) | Containers: images, registries, runtimes | [01](../../curriculum/01-containers.md) | Image that was never built (`ImagePullBackOff`) |
| [t1-02](02-pods/README.md) | Pods | [02b](../../curriculum/02-kubernetes-core/02b-pods-deployments.md) | `CrashLoopBackOff` from a bad command |
| [t1-03](03-deployments/README.md) | Deployments, rolling updates | [02b](../../curriculum/02-kubernetes-core/02b-pods-deployments.md) | Readiness probe on the wrong port |
| [t1-04](04-services-networking/README.md) | Services, DNS, NetworkPolicy | [02c](../../curriculum/02-kubernetes-core/02c-services-networking.md) | Service selector + targetPort bugs |
| [t1-05](05-config-secrets/README.md) | Namespaces, quotas, ConfigMaps, Secrets | [02d](../../curriculum/02-kubernetes-core/02d-namespaces-config-secrets.md) | Missing ConfigMap (`CreateContainerConfigError`) |
| [t1-06](06-storage/README.md) | PV, PVC, StorageClass | [02e](../../curriculum/02-kubernetes-core/02e-storage.md) | PVC asking for a StorageClass that doesn't exist |
| [t1-07](07-rbac/README.md) | RBAC, least privilege | [02f](../../curriculum/02-kubernetes-core/02f-rbac.md) | Broken RoleBinding; fix it *without over-granting* |
| [t1-08](08-crds-operators/README.md) | CRDs, controllers, finalizers | [02g](../../curriculum/02-kubernetes-core/02g-crds-operators.md) | Object stuck in `Terminating` |
| [t1-09](09-kubectl-fluency/README.md) | kubectl fluency | [02a](../../curriculum/02-kubernetes-core/02a-architecture-kubectl.md) | Wrong default namespace: "the cluster is empty!" |

Suggested order: 01 → 08, then 09 as a capstone. Tear down with `./labctl cluster down` when
you're done with the tier.
