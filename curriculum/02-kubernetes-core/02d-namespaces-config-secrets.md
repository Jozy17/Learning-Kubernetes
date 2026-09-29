# 02d - Namespaces, ConfigMaps and Secrets

**Lab:** [t1-05](../../labs/tier1/05-config-secrets/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~20 min

## 1. Namespaces
A **namespace** is a named scope for objects. It gives you:
- **names**: `web` in `team-a` and `web` in `team-b` are different objects
- **access control**: RoleBindings grant rights *within* a namespace (lab t1-07)
- **governance**: ResourceQuotas and LimitRanges apply per namespace
- **cleanup**: deleting a namespace deletes everything in it (every lab's cleanup relies on this)

Some objects are **cluster-scoped** and don't belong to any namespace: Nodes, PersistentVolumes,
StorageClasses, CRDs, ClusterRoles and Namespaces themselves.
`kubectl api-resources --namespaced=false` lists them.

System namespaces you'll see: `kube-system` (core components), `kube-public`, `kube-node-lease`,
and, on Harvester, `harvester-system`, `longhorn-system`, `cattle-system` and others.

> **Nutanix mapping:** a namespace + quota + RoleBinding is roughly a Prism Central **Project**:
> a boundary for a team, with a resource budget and role assignments. In Harvester you create
> VMs *in a namespace*, and Rancher groups namespaces into **Projects**.

### ResourceQuota and LimitRange
- **ResourceQuota** caps the namespace's total: number of pods, sum of CPU/memory requests and
  limits, storage, object counts.
- **LimitRange** sets per-container defaults and min/max values. It's needed in practice: once a
  quota covers `requests.cpu`, pods that don't set a request are rejected, unless a LimitRange
  supplies a default.

## 2. ConfigMaps
Configuration that shouldn't be baked into the image: settings, feature flags, whole config
files. You can consume it:
- as **environment variables** (`env.valueFrom.configMapKeyRef`, or `envFrom`), read once at
  container start
- as **files** through a volume. The kubelet updates these files after the ConfigMap changes
  (eventually, not instantly), except when mounted with `subPath`.

## 3. Secrets
Built like ConfigMaps, for sensitive data: passwords, tokens, TLS keys, registry credentials.
- Values are **base64-encoded, not encrypted**. Anyone with `get` on Secrets can read them.
- Protections are **layered**:
  1. **RBAC**: restrict `get/list/watch` on Secrets. Note that `list` also returns the values!
  2. **Encryption at rest** in etcd (API server `EncryptionConfiguration`, ideally with a KMS
     provider).
  3. **Least exposure**: mount as files with tight `defaultMode` rather than env vars; use
     separate namespaces for separate trust levels.
  4. **External secret managers** (Vault, cloud KMS) synced in by an operator. Never commit
     Secrets to git unencrypted (tools such as SOPS or Sealed Secrets exist for GitOps).
- Types: `Opaque` (generic), `kubernetes.io/tls`, `kubernetes.io/dockerconfigjson` (pull
  secrets), and others.

> **Harvester relevance:**
> - VM **cloud-init user data** is stored in Secrets, and it often contains passwords or SSH
>   keys.
> - **vm-import-controller** reads vCenter credentials from a Secret that your `VmwareSource`
>   references (Tier 4).
> - So in a migration, RBAC on the Harvester namespaces that hold those Secrets is part of your
>   security design. In this repo every such credential is a placeholder, and `.env` is
>   git-ignored.

## Official docs
- Namespaces - <https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/>
- Resource quotas - <https://kubernetes.io/docs/concepts/policy/resource-quotas/>
- Limit ranges - <https://kubernetes.io/docs/concepts/policy/limit-range/>
- ConfigMaps - <https://kubernetes.io/docs/concepts/configuration/configmap/>
- Secrets - <https://kubernetes.io/docs/concepts/configuration/secret/>
- Good practices for Secrets - <https://kubernetes.io/docs/concepts/security/secrets-good-practices/>
- Encrypting data at rest - <https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/>

## Key terms
namespace · cluster-scoped · ResourceQuota · LimitRange · ConfigMap · Secret · base64 ·
encryption at rest · envFrom · projected/mounted volume · cloud-init user data
