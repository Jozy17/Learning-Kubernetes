# 02f - RBAC: authentication, authorization, least privilege

**Lab:** [t1-07](../../labs/tier1/07-rbac/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~25 min

## 1. Every API request passes three gates
```
request ─▶ Authentication ─▶ Authorization ─▶ Admission control ─▶ etcd
           "who are you?"    "may you do X?"   "is this object OK / should we change it?"
```
1. **Authentication (authN).** Kubernetes has **no user database**. It trusts credentials:
   - X.509 client certificates (kind's admin kubeconfig)
   - bearer tokens (ServiceAccount tokens)
   - OIDC from an identity provider. Rancher can front AD/LDAP/SAML/OIDC for downstream
     clusters, including Harvester.
2. **Authorization (authZ).** Normally **RBAC**. It answers yes or no for
   (user/groups, verb, resource, namespace).
3. **Admission.** Controllers that validate or mutate objects: LimitRange defaults, Pod
   Security Admission, webhooks such as Harvester's own validators, and policy engines.

## 2. RBAC building blocks
| Object | Scope | Contains |
|---|---|---|
| **Role** | Namespace | Rules: `apiGroups` + `resources` + `verbs` |
| **ClusterRole** | Cluster | The same rules, reusable anywhere, and able to cover cluster-scoped resources |
| **RoleBinding** | Namespace | Grants a Role **or a ClusterRole** to subjects *in that namespace* |
| **ClusterRoleBinding** | Cluster | Grants a ClusterRole to subjects **everywhere** |

- **Subjects:** `User`, `Group`, `ServiceAccount` (namespace/name).
- **Verbs:** `get list watch create update patch delete deletecollection`, plus special ones:
  `escalate`, `bind`, `impersonate`, `use`.
- **Purely additive:** there are no deny rules. You remove access by removing grants.
- **roleRef is immutable** in a binding. To change it, delete and recreate the binding.

Built-in ClusterRoles to know:
- `cluster-admin`: everything
- `admin`: full control within a namespace, including RBAC there
- `edit`: read and write most objects, but no RBAC changes
- `view`: read-only, **excluding Secrets**

## 3. ServiceAccounts
Identities for **workloads and automation**. Every namespace has a `default` ServiceAccount.
Pods get a short-lived, automatically rotated token (a projected volume) unless you set
`automountServiceAccountToken: false`. `kubectl create token` issues time-limited tokens. The
old pattern of non-expiring token Secrets should be avoided.

## 4. Least privilege in practice
- Grant **namespaced** Roles through RoleBindings. Use ClusterRoleBindings only for truly
  cluster-wide duties.
- Treat these as **privileged** even though they don't look it:
  - `create pods` in a namespace: the pod can mount any Secret and use any ServiceAccount in
    that namespace
  - `get/list secrets`
  - `escalate`, `bind`, `impersonate`
  - write access to RBAC objects
  - `create` on `nodes/proxy`, or exec into pods
- Wildcards (`*`) in production Roles are a red flag.
- Audit regularly: `kubectl auth can-i --list --as=...`, review ClusterRoleBindings to
  `cluster-admin`, and check which groups your IdP maps in.

> **Security+/CySA+ mapping:**
> - RBAC is **role-based access control** with **implicit deny**.
> - ServiceAccounts are **service accounts / non-person entities**.
> - Short-lived tokens reduce the **credential-theft window**.
> - `kubectl auth can-i` plus binding reviews are your **access review / entitlement audit**.
> - Kubernetes **audit logs** (an API server setting) are your SIEM source.

## 5. Nutanix and Harvester mapping
| Nutanix | Kubernetes / Harvester |
|---|---|
| Prism local users / AD role mapping | Authentication via certs/tokens; in Harvester usually through Rancher or its own auth settings |
| Roles: Viewer / Operator / Admin | ClusterRoles `view` / `edit` / `admin` (plus Harvester- and Rancher-specific roles) |
| Projects (Prism Central) | Namespaces, grouped into **Rancher Projects** |
| Role assigned to a project | RoleBinding in each of the project's namespaces |

## Official docs
- Controlling access to the API - <https://kubernetes.io/docs/concepts/security/controlling-access/>
- Using RBAC authorization - <https://kubernetes.io/docs/reference/access-authn-authz/rbac/>
- RBAC good practices - <https://kubernetes.io/docs/concepts/security/rbac-good-practices/>
- Service accounts - <https://kubernetes.io/docs/concepts/security/service-accounts/>
- Auditing - <https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/>

## Key terms
authentication · authorization · admission · Role · ClusterRole · RoleBinding ·
ClusterRoleBinding · subject · verb · ServiceAccount · bound token · impersonation ·
least privilege · `auth can-i`
