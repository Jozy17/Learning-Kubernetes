# Lab t1-04: Services, DNS and network policy

**Curriculum:** [02c - Services & Networking](../../../curriculum/02-kubernetes-core/02c-services-networking.md) · **Time:** ~60 min

## Objectives
1. Explain why pods need a **Service** in front of them (pod IPs change).
2. Create a **ClusterIP** Service and reach it by **DNS name** from another pod.
3. Read **EndpointSlices** to see which pods a Service actually sends traffic to.
4. Expose an app outside the cluster with a **NodePort**.
5. Write **NetworkPolicies** (default-deny, then allow), and understand who enforces them.

> **Nutanix mapping**
> - **Pod network:** every pod gets its own IP on a flat, cluster-internal network. The CNI
>   plugin (here `kindnet`) builds it, much as AHV's OVS bridge builds VM networking. These IPs
>   aren't on your physical VLANs.
> - **Service:** a stable virtual IP plus a DNS name that load-balances across matching pods.
>   Think of a load balancer VIP in front of a VM pool, except that Kubernetes keeps the member
>   list updated automatically using **labels**.
> - **NetworkPolicy:** a pod-level firewall, similar in spirit to **Flow microsegmentation**
>   rules that are based on categories. Here the "categories" are pod labels.
> - **Coming later (Harvester):** VMs in Harvester usually attach to **VLAN networks** through
>   Multus bridges. That traffic goes directly onto your physical network and **doesn't** pass
>   through Services or NetworkPolicies. Keep that difference in mind for Tier 3.

## Based on (official docs)
- Service - <https://kubernetes.io/docs/concepts/services-networking/service/>
- DNS for Services and Pods - <https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/>
- EndpointSlices - <https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/>
- Network Policies - <https://kubernetes.io/docs/concepts/services-networking/network-policies/>
- Debug Services - <https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/>
- kind extraPortMappings - <https://kind.sigs.k8s.io/docs/user/configuration/#extra-port-mappings>

## Setup
```bash
./labctl start t1-04
```
Setup deploys `web`, three nginx pods that each answer "served by `<pod-name>`", and a client
pod `toolbox` that has `curl`.

---

## Tasks

### Task 1 - Why a Service? Pod IPs are not stable
```bash
kubectl -n lab-net get pods -o wide                    # note the IPs
kubectl -n lab-net delete pod -l app=web --wait=false
kubectl -n lab-net get pods -o wide                    # new pods, new IPs
```
Anything that hard-coded a pod IP is now broken. Put a Service in front of the pods:
```bash
kubectl -n lab-net expose deployment web --port=80 --target-port=80
kubectl -n lab-net get svc web                          # CLUSTER-IP is stable for the Service's life
kubectl -n lab-net get svc web -o yaml | grep -A3 selector
```

### Task 2 - Endpoints: who's behind the Service?
```bash
kubectl -n lab-net get endpointslices -l kubernetes.io/service-name=web -o wide
kubectl -n lab-net describe svc web | grep -i endpoints
```
**Why this matters:** when a Service "doesn't work", the first question is always *does it
have endpoints?* No endpoints means the selector matches no **ready** pods.

### Task 3 - DNS and load balancing
```bash
kubectl -n lab-net exec toolbox -- curl -s http://web                          # short name (same namespace)
kubectl -n lab-net exec toolbox -- curl -s http://web.lab-net.svc.cluster.local  # fully qualified
for i in 1 2 3 4 5 6; do kubectl -n lab-net exec toolbox -- curl -s http://web; done
kubectl -n lab-net exec toolbox -- cat /etc/resolv.conf                          # search domains
```
You should see different pod names answering. The DNS name has the form
`<service>.<namespace>.svc.cluster.local`, and the `search` line in `resolv.conf` is what makes
the short name `web` work.

### Task 4 - Reach it from outside: NodePort
Create `work/web-nodeport.yaml` yourself:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
  namespace: lab-net
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - port: 80          # the Service's own port (inside the cluster)
    targetPort: 80    # the container port on the pods
    nodePort: 30080   # opened on EVERY node's IP (range 30000-32767)
```
```bash
kubectl apply -f labs/tier1/04-services-networking/work/web-nodeport.yaml
curl -s http://localhost:30080     # from your WSL shell - kind maps this port to the control-plane node
```
From Windows you can also browse to <http://localhost:30080>, because WSL forwards localhost.

**Three kinds of port, often confused:**
- `targetPort` is the port the container listens on.
- `port` is the Service's port inside the cluster.
- `nodePort` is the port opened on every node for traffic from outside.

A `LoadBalancer` Service goes one step further and asks an external load balancer for an IP.
Harvester has a built-in load balancer for that, which Tier 3 covers.

### Task 5 - Port-forward, for comparison
```bash
kubectl -n lab-net port-forward svc/web 8080:80
# second terminal: curl -s localhost:8080   (then Ctrl+C in the first)
```
Port-forward is a debugging tunnel for one user. A NodePort is a real, shared entry point.

### Task 6 - Network policy: default deny, then allow
Write `work/netpol.yaml`:
```yaml
# 1) Deny ALL incoming traffic to every pod in the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: lab-net
spec:
  podSelector: {}          # {} = every pod in this namespace
  policyTypes: [Ingress]   # we only restrict incoming traffic
---
# 2) Allow ONLY pods labelled role=toolbox to reach app=web on TCP 80
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-toolbox-to-web
  namespace: lab-net
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: toolbox
    ports:
    - protocol: TCP
      port: 80
```
```bash
kubectl apply -f labs/tier1/04-services-networking/work/netpol.yaml
kubectl -n lab-net exec toolbox -- curl -s -m 5 http://web          # allowed
kubectl -n lab-net run intruder --image=busybox:1.37 --restart=Never --rm -it -- wget -qO- -T 3 http://web
#   expected: timeout (blocked) - if you get a page, read "Enforcement" below
```

#### Enforcement: a security lesson
A NetworkPolicy is **only a request**. The **CNI plugin** has to enforce it, and a CNI that
doesn't support policies accepts the objects **without complaint** and ignores them. kind's
`kindnet` enforces policies using nftables in recent versions, but only when the host kernel has
the needed features. If your `intruder` pod still got through, you have just seen that failure
mode for yourself.

- **In an audit, "we have NetworkPolicies" proves nothing.** Test that they're enforced, as you
  just did.
- **Harvester:** RKE2 in Harvester uses **Canal** (Calico policy + Flannel), which does enforce
  policies for pods. But as the mapping box says, VM traffic on the default VLAN networks
  bypasses them. VM micro-segmentation needs the (experimental) Kube-OVN add-on; see
  [02c](../../../curriculum/02-kubernetes-core/02c-services-networking.md).

`./labctl verify` checks your policy objects, and it also prints whether your cluster enforced
them.

## Check your work
```bash
./labctl verify t1-04
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-04
```
`curl http://api` from `toolbox` fails, even though the api pods are healthy. There are **two**
bugs in the Service, and you may only change the Service.

<details><summary>Hint 1</summary>

`kubectl -n lab-net get endpointslices -l kubernetes.io/service-name=api`: are there any
endpoints? Then compare `kubectl -n lab-net get svc api -o jsonpath='{.spec.selector}'` with
`kubectl -n lab-net get pods -l app=api --show-labels`.
</details>

<details><summary>Hint 2</summary>

Fix the selector with `kubectl -n lab-net edit svc api`. Once there are endpoints, does curl work
yet? Which port does nginx listen on, and which `targetPort` does the Service send to?
</details>

<details><summary>Hint 3</summary>

Set `selector: {app: api}` and `targetPort: 80`. In real life, a
`kubectl port-forward pod/<api-pod> 8080:80` test bypasses the Service entirely and proves the
pods themselves are fine. That's a quick way to split the problem in half.
</details>

Check: `./labctl breakfix t1-04 --check`

## Cleanup
```bash
./labctl cleanup t1-04
```

## Review questions
1. Why shouldn't clients connect to pod IPs directly?
2. What decides which pods a Service sends traffic to? Why does a pod that isn't ready get no
   traffic?
3. What's the fully qualified DNS name of Service `db` in namespace `payments`?
4. Explain `port`, `targetPort` and `nodePort` in one sentence each.
5. A Service has zero endpoints. List three possible causes.
6. Your cluster accepted a NetworkPolicy, but traffic isn't blocked. Why might that be?
7. In Harvester, will a NetworkPolicy protect a VM attached to a VLAN network? Why or why not?
