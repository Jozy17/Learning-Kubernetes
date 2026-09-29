# 01 - Containers: images, registries, runtimes

**Lab:** [t1-01](../labs/tier1/01-containers/README.md) · **Quiz:** `./labctl quiz 01` · **Reading time:** ~30 min

Before Kubernetes makes sense, you need a clear mental model of what a container is. This matters
more than usual for you: Harvester runs **VMs** on a platform built for **containers**, and you'll
constantly move between the two worlds.

## 1. A container is a process, not a small VM

| | VM (AHV/ESXi) | Container |
|---|---|---|
| What's isolated | A whole machine: virtual hardware, its own kernel | A **process tree**, on the host's kernel |
| Boots | A guest OS (seconds to minutes) | Nothing to boot; the process just starts (milliseconds) |
| Isolation mechanism | Hardware virtualization (VT-x / AMD-V) | Linux **namespaces** (what the process can *see*) + **cgroups** (what it can *use*) |
| Size | GBs (a full OS) | MBs (the app plus the libraries it needs) |
| Security boundary | Strong (hypervisor) | Weaker (shared kernel), so extra hardening matters |

**Namespaces** give a process its own view of PIDs, network interfaces, mounts, hostname and
users. **cgroups** cap its CPU and memory. Together they make one process look like a machine
to itself. You saw this in lab t1-01, where `ps` inside the container showed httpd as PID 1.

> **Security lens (CySA+):** because containers share the host kernel, a kernel exploit or a
> misconfiguration (privileged containers, host mounts, running as root) can lead to escaping to
> the host. That's why lab t1-01 made you run as UID 65534, and why Kubernetes has Pod Security
> Standards. This is also exactly why KubeVirt exists: when you need a **hard** boundary or a
> **different OS/kernel** (Windows!), you run a real VM.

## 2. Images: layered, read-only templates

An **image** is a stack of read-only filesystem **layers** plus a small JSON **config**, which
holds the default command, environment, user and exposed ports.

- Each Dockerfile instruction that changes files (`COPY`, `RUN`, ...) adds a layer.
- Layers are content-addressed by SHA-256 and **shared**: 50 images built `FROM busybox` store
  busybox once.
- When a container starts, the runtime adds a thin **writable layer** on top. Anything written
  there disappears with the container. That's why lab t1-06 is about persistent volumes.

**Nutanix analogy:** an image is like a golden image in the Image Service combined with linked
clones. The shared read-only base is like Nutanix shadow clones/snapshots, and the writable layer
is the clone's delta.

### Image references
```
registry.example.com/team/app:1.4.2@sha256:ab12...
└──── registry ────┘ └─ repo ─┘ └tag┘ └── digest ──┘
```
- No registry means `docker.io`. A single-word name means `docker.io/library/<name>`.
- A **tag** is a mutable pointer, which someone can re-push. A **digest** is immutable: the
  hash of the content.
- **Pin by digest** for anything important. This repo pins the kind node image that way, in
  `versions.env`.

### Multi-architecture images
One tag can point to an **index** that lists images for amd64, arm64 and other architectures.
The runtime picks the one that matches the node. You met a side effect of this in the lab setup:
`labctl` exports only your architecture before loading images into kind.

## 3. Registries

A **registry** is an HTTP API that stores images (the `/v2/` API you queried with `curl`).
Examples are Docker Hub, `registry.k8s.io`, GitHub `ghcr.io`, Quay, Harbor and the SUSE
Registry. Things to know for your new job:
- **Pull secrets:** private registries need credentials. In Kubernetes those are
  `imagePullSecrets`.
- **Rate limits:** Docker Hub throttles anonymous pulls. Clusters often use a **mirror** or a
  pull-through cache.
- **Air-gapped installs:** Harvester supports air-gapped installation. Its ISO carries the
  images it needs for install, and extra images come from a private registry. We'll revisit
  this in Tier 3.

## 4. Runtimes: who actually runs the container?

```
kubectl ──▶ API server ──▶ kubelet (on the node) ──CRI──▶ containerd ──▶ runc ──▶ Linux kernel
docker CLI ──▶ dockerd ─────────────────────────────────▶ containerd ──▶ runc ──▶ Linux kernel
```
- **runc** is the low-level runtime. It sets up namespaces and cgroups and starts the process
  (the OCI runtime spec).
- **containerd** is the high-level runtime. It pulls images, manages snapshots and supervises
  containers.
- **CRI** (Container Runtime Interface) is the gRPC API the **kubelet** uses to talk to a
  runtime. Kubernetes dropped direct Docker support ("dockershim") in v1.24, so nodes use
  containerd or CRI-O directly.
- **Docker** is a developer tool that also uses containerd underneath. The images it builds are
  standard **OCI images** that any runtime can run.
- **Harvester:** RKE2 bundles **containerd**. On a Harvester node you debug containers with
  `crictl` (as in lab t1-01), not `docker`.

Every pod also has a tiny **pause** container, which holds the pod's network namespace so the
app containers can come and go while the pod IP stays the same.

## 5. How this connects to VMs (preview of Tier 2)
KubeVirt runs each VM **inside a pod**. The pod's main container (`virt-launcher`) runs
**libvirt + QEMU/KVM**, the same KVM stack that AHV is built on. So a Harvester VM is "a KVM
process inside a container inside a pod". The container provides the scheduling, networking
and storage plumbing, and KVM provides the hard isolation.

## Official docs
- Kubernetes: Images - <https://kubernetes.io/docs/concepts/containers/images/>
- Kubernetes: Container runtimes - <https://kubernetes.io/docs/setup/production-environment/container-runtimes/>
- Dockerfile reference - <https://docs.docker.com/reference/dockerfile/>
- OCI image spec - <https://github.com/opencontainers/image-spec>
- Dockershim removal FAQ - <https://kubernetes.io/blog/2022/02/17/dockershim-faq/>

## Key terms
image · layer · container · namespace (Linux) · cgroup · registry · tag · digest · OCI · runc ·
containerd · CRI · crictl · pause container · multi-arch index
