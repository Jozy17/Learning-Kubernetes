# Lab t1-07: RBAC: least privilege for people and workloads

**Curriculum:** [02f - RBAC](../../../curriculum/02-kubernetes-core/02f-rbac.md) · **Time:** ~60 min

## Objectives
1. Explain **authentication vs authorization** in Kubernetes, and where RBAC fits.
2. Create **ServiceAccounts**, **Roles** and **RoleBindings**, and test them with
   `kubectl auth can-i --as`.
3. Reuse built-in **ClusterRoles** (`view`, `edit`) in a single namespace.
4. Issue a short-lived token and call the API with it.
5. Fix broken RBAC **without over-granting**, which is the real-world skill.

> **Security mapping (Security+/CySA+ terms)**
> - **Subject → verb → resource → scope** is classic RBAC. A *Role* is a permission set, and a
>   *RoleBinding* assigns it to subjects within **one namespace**.
>   *ClusterRole/ClusterRoleBinding* do the same **cluster-wide**.
> - **ServiceAccount:** a non-human identity for workloads and automation, like a service
>   account in AD. Kubernetes has no user database. Humans authenticate through certificates or
>   OIDC (Rancher often acts as the OIDC front-end), and *are* whatever the credential says.
> - **Default deny:** RBAC is purely additive. There are no "deny" rules, and anything not
>   granted is forbidden.
>
> **Nutanix mapping:** Prism roles (Viewer / Operator / Cluster Admin) plus Prism Central
> **Projects**, where a role applies to a scope, correspond to ClusterRoles (`view` / `edit` /
> `admin`) plus namespaces. In Harvester and Rancher, **Projects** group namespaces and bind
> roles to them in the same way.

## Based on (official docs)
- Using RBAC authorization - <https://kubernetes.io/docs/reference/access-authn-authz/rbac/>
- Service accounts - <https://kubernetes.io/docs/concepts/security/service-accounts/>
- RBAC good practices - <https://kubernetes.io/docs/concepts/security/rbac-good-practices/>
- `kubectl auth can-i` - <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/>
- `kubectl create token` - <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_token/>

## Setup
```bash
./labctl start t1-07
```
Setup creates namespaces `lab-rbac` and `lab-rbac-other`, a Deployment `app`, a Secret
`payment-api-key` with a placeholder value, and a ConfigMap in the other namespace.

---

## Tasks

### Task 1 - Who are you right now?
```bash
kubectl auth whoami
kubectl auth can-i '*' '*' --all-namespaces         # yes - you are cluster-admin (kind's admin cert)
kubectl config view --minify -o jsonpath='{.users[0].name}{"\n"}'
```
**Why this matters:** kind hands you an all-powerful client certificate, like logging into Prism
as `admin`. That's fine for a lab and a bad habit anywhere else. The rest of this lab builds
narrower identities.

### Task 2 - An auditor that can read pods and logs, and nothing else
```bash
kubectl -n lab-rbac create serviceaccount auditor
kubectl -n lab-rbac create role pod-reader --verb=get,list,watch --resource=pods,pods/log
kubectl -n lab-rbac create rolebinding auditor-pod-reader --role=pod-reader --serviceaccount=lab-rbac:auditor
kubectl -n lab-rbac get role pod-reader -o yaml        # read the rules you just created
```
Test it by **impersonating** the ServiceAccount:
```bash
AS=system:serviceaccount:lab-rbac:auditor
kubectl auth can-i list pods        -n lab-rbac       --as=$AS   # yes
kubectl auth can-i get pods/log     -n lab-rbac       --as=$AS   # yes
kubectl auth can-i get secrets      -n lab-rbac       --as=$AS   # no
kubectl auth can-i delete pods      -n lab-rbac       --as=$AS   # no
kubectl auth can-i list pods        -n lab-rbac-other --as=$AS   # no - Roles stop at the namespace
kubectl auth can-i --list           -n lab-rbac       --as=$AS   # everything it can do
```

### Task 3 - A deployer for CI/CD
Write this one as YAML, `work/deployer.yaml`, so that you see the full structure:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployer
  namespace: lab-rbac
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deploy-manager
  namespace: lab-rbac
rules:
- apiGroups: ["apps"]                 # Deployments live in the "apps" API group
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]                     # "" = the core group (pods, services, ...)
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deployer-deploy-manager
  namespace: lab-rbac
subjects:
- kind: ServiceAccount
  name: deployer
  namespace: lab-rbac
roleRef:                              # immutable once created!
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deploy-manager
```
```bash
kubectl apply -f labs/tier1/07-rbac/work/deployer.yaml
kubectl auth can-i create deployments -n lab-rbac --as=system:serviceaccount:lab-rbac:deployer   # yes
kubectl auth can-i create deployments -n default  --as=system:serviceaccount:lab-rbac:deployer   # no
kubectl auth can-i get secrets        -n lab-rbac --as=system:serviceaccount:lab-rbac:deployer   # no
```

### Task 4 - Reuse a built-in ClusterRole, in one namespace only
```bash
kubectl describe clusterrole view | head -30          # read-only on most things - but NOT secrets
kubectl -n lab-rbac create serviceaccount viewer
kubectl -n lab-rbac create rolebinding viewer-view --clusterrole=view --serviceaccount=lab-rbac:viewer
kubectl auth can-i list deployments -n lab-rbac       --as=system:serviceaccount:lab-rbac:viewer   # yes
kubectl auth can-i list deployments -n lab-rbac-other --as=system:serviceaccount:lab-rbac:viewer   # no
```
**Pattern to remember:** a *RoleBinding* can point at a *ClusterRole*. The permissions are
defined once, cluster-wide, and granted only inside the binding's namespace. Rancher and
Harvester project roles work this way.

### Task 5 - Use a real token, not impersonation
```bash
TOKEN=$(kubectl -n lab-rbac create token auditor --duration=10m)   # short-lived, signed JWT
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl --kubeconfig=/dev/null --server="$SERVER" --token="$TOKEN" --insecure-skip-tls-verify \
  -n lab-rbac get pods                           # works
kubectl --kubeconfig=/dev/null --server="$SERVER" --token="$TOKEN" --insecure-skip-tls-verify \
  -n lab-rbac get secrets                        # Forbidden
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null; echo    # peek at the JWT claims (exp = expiry)
```
> **Why `--kubeconfig=/dev/null`:** without it, kubectl *also* sends your admin client
> certificate from `~/.kube/config`. The API server checks certificates before tokens, so you'd
> quietly be admin again, and the secrets command would "work". Always make sure you're testing
> the identity you think you're testing.
>
> `--insecure-skip-tls-verify` is acceptable **only** in this throwaway lab. It skips checking
> the API server's certificate. In real use you'd pass the cluster CA instead. The token itself
> expires in 10 minutes, which is the modern default and much safer than the old non-expiring
> ServiceAccount token Secrets.

### Task 6 - Audit: who can read secrets?
```bash
for sa in auditor deployer viewer; do
  printf '%-9s ' $sa; kubectl auth can-i get secrets -n lab-rbac --as=system:serviceaccount:lab-rbac:$sa
done
kubectl get rolebindings -n lab-rbac -o wide
```
In a real review you'd also check ClusterRoleBindings and groups. The good-practices page
linked above lists privilege-escalation paths to watch for, such as `escalate`, `bind`,
`impersonate`, and creating pods in privileged namespaces.

## Check your work
```bash
./labctl verify t1-07
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-07
```
The CI ServiceAccount `ci-bot` gets `Forbidden`. Fix it with **exactly** the permissions it
needs. The check fails if you over-grant (for example with `cluster-admin`, `delete` or secrets
access).

<details><summary>Hint 1</summary>

Reproduce with the `--dry-run=server` command from the ticket, then look at
`kubectl -n lab-rbac get rolebinding ci-bot-binding -o yaml`. Who exactly is the subject?
</details>

<details><summary>Hint 2</summary>

There are two problems:
1. The RoleBinding's subject is `ci-bot` in namespace **`default`**, but the ServiceAccount
   lives in `lab-rbac`.
2. The Role only has `get, list, watch`, and `set image` needs **`patch`**.
</details>

<details><summary>Hint 3</summary>

`kubectl -n lab-rbac edit rolebinding ci-bot-binding` and change the subject's namespace. The
`subjects` field *can* be edited, but `roleRef` can't. Then add `patch` to the Role with
`kubectl -n lab-rbac edit role ci-deployer`.
</details>

Check: `./labctl breakfix t1-07 --check`

## Cleanup
```bash
./labctl cleanup t1-07
```

## Review questions
1. What's the difference between a Role and a ClusterRole, and between a RoleBinding and a
   ClusterRoleBinding?
2. Why is it useful to bind a *ClusterRole* with a *RoleBinding*?
3. RBAC has no deny rules. How do you "take away" a permission?
4. What's the risk of granting `create pods` in a namespace, even without secrets access?
   (Think: a pod can mount any secret in its namespace.)
5. Why are short-lived tokens from `kubectl create token` better than long-lived token Secrets?
6. The built-in `view` role excludes Secrets. Why?
7. Map Prism's Viewer / Operator / Admin roles to Kubernetes built-in ClusterRoles.
