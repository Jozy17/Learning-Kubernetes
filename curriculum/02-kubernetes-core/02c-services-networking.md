# 02c - Services and networking

**Lab:** [t1-04](../../labs/tier1/04-services-networking/README.md) · **Quiz:** `./labctl quiz 02` · **Reading time:** ~30 min

## 1. The Kubernetes network model
Kubernetes requires a flat network in which:
1. every pod gets its **own IP address**,
2. every pod can reach every other pod **without NAT**, on any node, and
3. agents on a node (such as the kubelet) can reach that node's pods.

The network itself is built by a **CNI plugin**. kind uses `kindnet`. Harvester's RKE2 uses
**Canal** (Flannel VXLAN for connectivity plus Calico for NetworkPolicy). Pod IPs come from a
cluster-internal range (the **pod CIDR**) and aren't on your physical VLANs.

> **Nutanix mapping:** on AHV, VMs attach to VLAN-backed networks on the OVS bridge `br0` and
> get IPs from your real network (or from IPAM). The Kubernetes pod network is a separate overlay
> that the CNI builds. Harvester has **both**: the pod network for its own services, and
> **VLAN-backed VM networks** (through Multus + bridges) that behave much like AHV networks.

## 2. Services: stable front doors
Pods come and go, and their IPs change (lab t1-04, Task 1). A **Service** gives you:
- a stable **virtual IP** (the ClusterIP) and **DNS name** `<svc>.<ns>.svc.cluster.local`
- load balancing across all **ready** pods that match its **label selector**
- automatically maintained **EndpointSlices**, the current list of backend pod IPs

| Type | Reachable from | Use |
|---|---|---|
| `ClusterIP` (default) | Inside the cluster | Service-to-service |
| `NodePort` | `<any node IP>:<30000-32767>` | Simple external access, labs |
| `LoadBalancer` | An external IP from a load-balancer implementation | Production external access. **Harvester ships its own load balancer** for this, which Tier 3 covers |
| `ExternalName` | DNS alias | Point at something outside the cluster |
| Headless (`clusterIP: None`) | DNS returns pod IPs directly | StatefulSets, custom discovery |

Ports to keep straight:
- `targetPort` is what the container listens on.
- `port` is the Service's own port.
- `nodePort` is opened on every node.

**kube-proxy** programs each node (with iptables, IPVS or nftables) so that traffic to a
ClusterIP is sent on to one of the endpoints.

### DNS
CoreDNS runs in `kube-system`. A pod's `/etc/resolv.conf` has search domains, so `web` resolves
within the same namespace, and `web.other-ns` resolves across namespaces.

### Debugging a Service, in order
1. Does the Service have **endpoints**? (`kubectl get endpointslices -l kubernetes.io/service-name=X`)
   - No: the selector doesn't match the pod labels, or the pods aren't **ready**.
2. Does the pod answer directly? (`kubectl port-forward pod/P 8080:<containerPort>`)
   - No: it's an app problem, not a network one.
3. Is `targetPort` the port the container actually listens on?
4. Does DNS resolve? (`nslookup svc` from a pod)
5. Is a NetworkPolicy blocking the traffic?

## 3. Ingress and Gateway (awareness)
An **Ingress** or the newer **Gateway API** routes HTTP(S) by hostname and path to Services,
handling TLS termination. Harvester's UI is published this way. You won't need these much for
VM migrations.

## 4. NetworkPolicy: pod-level firewalling
- Without any policy, **all pod-to-pod traffic is allowed**.
- A policy **selects pods** (`podSelector`) and lists what's allowed **in** (`ingress`) and/or
  **out** (`egress`). Once a pod is selected by any policy for a direction, everything not
  explicitly allowed in that direction is denied.
- Rules match on pod labels, namespace labels and IP blocks, plus ports.
- **The CNI must enforce policies.** A cluster accepts NetworkPolicy objects whether or not
  anything enforces them (lab t1-04, "Enforcement").

> **Security mapping:** comparable to **Nutanix Flow** microsegmentation (category-based rules)
> or host firewalls, but scoped to pod labels. A common baseline is default-deny ingress per
> namespace, then explicit allows.
>
> **Harvester caveat:** VMs on the default **VLAN networks** (Multus + Linux bridge) send traffic
> directly onto the physical network. Kubernetes NetworkPolicy doesn't filter those bridge
> interfaces, so segmentation comes from your VLAN design and physical firewalls, as it does
> today. Harvester v1.9 also offers the **kubeovn-operator add-on** (still *experimental* as an
> add-on, although many Kube-OVN features are GA in v1.9.0). It lets you isolate VMs within a
> virtual switch network using NetworkPolicies or security groups, which is the closest thing to
> Flow. Source: Harvester v1.9 docs, "Kube-OVN Virtual Machine Isolation".

## 5. Multus: more than one network per pod (preview)
Standard Kubernetes gives each pod **one** interface. **Multus** is a "meta-CNI" that attaches
extra interfaces, defined by `NetworkAttachmentDefinition` objects. Harvester uses it to connect
VM NICs to VLAN networks, much like adding a NIC on a specific VLAN to an AHV VM.

## Official docs
- Cluster networking model - <https://kubernetes.io/docs/concepts/services-networking/>
- Service - <https://kubernetes.io/docs/concepts/services-networking/service/>
- DNS for Services and Pods - <https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/>
- Network Policies - <https://kubernetes.io/docs/concepts/services-networking/network-policies/>
- Debug Services - <https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/>
- Gateway API - <https://kubernetes.io/docs/concepts/services-networking/gateway/>
- Multus CNI - <https://github.com/k8snetworkplumbingwg/multus-cni>

## Key terms
CNI · pod CIDR · Service · ClusterIP · NodePort · LoadBalancer · EndpointSlice · selector ·
kube-proxy · CoreDNS · NetworkPolicy · default deny · Multus · NetworkAttachmentDefinition
