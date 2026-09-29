# Quiz 01 - Containers

Source: [curriculum/01-containers.md](../curriculum/01-containers.md) and lab t1-01.
Run with `./labctl quiz 01`.

### Q: What is the fundamental difference between a VM and a container?
**A:** A VM virtualises hardware and runs its own kernel. A container is an isolated process tree that shares the host's kernel.

### Q: Which two Linux kernel features make a process into a "container"?
**A:** Namespaces (what the process can see: PIDs, network, mounts, hostname, users) and cgroups (what it can use: CPU, memory).

### Q: What is an image layer, and why are layers shared between images?
**A:** A read-only filesystem diff created by one build step (COPY, RUN...). Layers are content-addressed by SHA-256, so identical layers are stored and downloaded only once.

### Q: Where do files written inside a running container go, and what happens to them?
**A:** Into a thin writable layer on top of the image. They are lost when the container is removed, unless they are written to a volume.

### Q: Expand the image reference `busybox:1.37` to its full form.
**A:** `docker.io/library/busybox:1.37`

### Q: Why is pinning an image by digest safer than by tag?
**A:** Tags are mutable, so someone can push different content under the same tag. A digest is the content's hash and can't change, which protects against tampering and surprise changes (supply-chain integrity).

### Q: What is a multi-architecture image?
**A:** An index (manifest list) that points to separate images per platform, such as amd64 and arm64. The runtime pulls the one that matches the node.

### Q: What do containerd, runc and CRI each do?
**A:** runc starts a single container (namespaces, cgroups). containerd manages images, snapshots and container lifecycles. CRI is the gRPC API the kubelet uses to talk to a runtime such as containerd.

### Q: Does a Kubernetes node (for example, a Harvester node) use Docker to run containers?
**A:** No. The kubelet talks CRI to containerd directly (dockershim was removed in v1.24). Use `crictl` on the node to inspect containers.

### Q: What is the "pause" container in every pod for?
**A:** It holds the pod's network namespace, so the pod keeps its IP while app containers restart.

### Q: Why did the kind nodes not see your locally built image until you ran `kind load`?
**A:** Each kind node has its own containerd image store, separate from your Docker daemon. A real cluster would pull the image from a registry instead.

### Q: Why does the lab Dockerfile use `USER 65534`, and why port 8080?
**A:** To run as an unprivileged user (least privilege, and less damage after a container escape). Traditionally only root may bind ports below 1024, so a non-root app listens on a high port.

### Q: Why is the shared kernel a security concern for containers?
**A:** A kernel exploit or a dangerous configuration (privileged mode, host mounts, running as root) can let a process escape to the host and every other container on it. VMs have a stronger hypervisor boundary.

### Q: How does a KubeVirt VM relate to containers?
**A:** The VM's QEMU/KVM process runs inside the `virt-launcher` container of a pod. Kubernetes provides scheduling, networking and storage, and KVM provides hardware isolation.

### Q: What does `ImagePullBackOff` mean, and what's the first command to run?
**A:** The kubelet can't pull the image (wrong name or tag, missing registry credentials, no network) and is backing off between retries. Run `kubectl describe pod <pod>` and read the Events.
