# Lab t1-01: Containers: images, registries, runtimes

**Curriculum:** [01 - Containers](../../../curriculum/01-containers.md) · **Time:** ~45 min

## Objectives
By the end of this lab you can:
1. Explain the difference between an **image** and a **container**, and what image **layers** are.
2. Write a small Dockerfile that runs as a **non-root** user, and build it.
3. Run, inspect, exec into, and stop a container with Docker.
4. Tag and push an image to a **registry**, and read the registry API.
5. Get a locally built image into Kubernetes, and see that Kubernetes uses **containerd**,
   not Docker, as its runtime.

> **Nutanix mapping**
> - An **image** is like a golden disk image in the Prism Image Service. It's read-only, and
>   you start many copies from it.
> - A **container** is like a VM cloned from that image. The difference is that a container
>   shares the host kernel, has no guest OS, and starts in milliseconds.
> - A **registry** is like the Image Service, but reached over HTTP by every node.
> - The **container runtime** (containerd) plays the part AHV plays for VMs. It's the component
>   on each node that actually starts the workloads.

## Based on (official docs)
- Kubernetes: Images - <https://kubernetes.io/docs/concepts/containers/images/>
- Kubernetes: Container runtimes - <https://kubernetes.io/docs/setup/production-environment/container-runtimes/>
- Dockerfile reference - <https://docs.docker.com/reference/dockerfile/>
- kind: loading an image into your cluster - <https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster>
- Distribution registry HTTP API - <https://distribution.github.io/distribution/spec/api/>

## Setup
```bash
./labctl cluster up        # once; skip if the cluster already exists
./labctl start t1-01
```
Setup creates the namespace `lab-containers`, pulls `busybox:1.37`, starts a private registry
on `localhost:5001`, and creates the `work/` folder in this lab directory.

---

## Tasks
Type these commands yourself. The output is the lesson.

### Task 1 - Look inside an image
```bash
docker image ls busybox
docker image history busybox:1.37        # each line is a layer; busybox has very few
docker image inspect busybox:1.37 --format '{{.Os}}/{{.Architecture}}  entrypoint={{.Config.Cmd}}'
```
**Why:** an image is a stack of read-only filesystem layers plus metadata, such as the default
command. It contains no kernel, because containers use the host's kernel.

### Task 2 - Write and build your own image
```bash
cd labs/tier1/01-containers/work
cat > index.html <<'EOF'
<h1>Hello from my first container image</h1>
EOF
```
Now create a file called `Dockerfile` in the same folder. Type it yourself, one instruction at a
time, and read the comment on each line:
```dockerfile
# Start from a tiny base image (a layer we don't have to build)
FROM busybox:1.37
# Copy our content into the image - this creates a new layer
COPY index.html /www/index.html
# Document the port the app listens on (metadata only; it doesn't publish anything)
EXPOSE 8080
# Run as 'nobody' (UID 65534), not root - least privilege, like not logging into Prism as admin
USER 65534
# The process the container runs. When it exits, the container stops.
CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
```
Build it and look at the result:
```bash
docker build -t hello-web:1.0 .
docker image history hello-web:1.0      # your COPY layer sits on top of busybox's layers
docker image inspect hello-web:1.0 --format 'user={{.Config.User}} cmd={{.Config.Cmd}}'
```

### Task 3 - Run it as a container
```bash
docker run -d --name hello-web -p 127.0.0.1:8081:8080 hello-web:1.0
docker ps                                  # STATUS "Up", port mapping shown
curl http://localhost:8081/                # your page
docker logs hello-web                      # httpd -v logs each request
docker exec hello-web id                   # uid=65534 - not root
docker exec hello-web ps                   # PID 1 is httpd: a container is "just a process"
docker stop hello-web && docker rm hello-web
```
**Why port 8080 and not 80:** traditionally only root may bind ports below 1024. Running as
non-root with a high port avoids needing extra privileges. Many hardened images
(Bitnami, Red Hat UBI) follow the same pattern.

### Task 4 - Push to a registry
Before anyone else can use an image, it has to be in a registry.
```bash
docker tag hello-web:1.0 localhost:5001/hello-web:1.0   # the name includes the registry host
docker push localhost:5001/hello-web:1.0
curl -s http://localhost:5001/v2/_catalog                 # {"repositories":["hello-web"]}
curl -s http://localhost:5001/v2/hello-web/tags/list      # {"name":"hello-web","tags":["1.0"]}
```
**Why the name changed:** an image reference is `registry/repository:tag`. When there's no
registry part (`busybox:1.37`), Docker assumes `docker.io/library/busybox:1.37`. Keep that in
mind when you read Harvester and KubeVirt manifests.

> **Security note:** tags are mutable, because someone can push a different image under the
> same tag. Production manifests often pin by **digest** (`image@sha256:...`), and this repo
> pins the kind node image that way. Check the digest with:
> `docker image inspect localhost:5001/hello-web:1.0 --format '{{index .RepoDigests 0}}'`

### Task 5 - Run the image in Kubernetes
The kind nodes are separate "machines", and they can't see your local Docker images. Copy the
image into every node:
```bash
kind load docker-image hello-web:1.0 --name k8slab
kubectl -n lab-containers run hello-web --image=hello-web:1.0 --port=8080
kubectl -n lab-containers get pod hello-web -o wide      # which node did it land on?
kubectl -n lab-containers exec hello-web -- wget -qO- http://localhost:8080/
```
> Why no `imagePullPolicy` flag: for any tag other than `:latest`, Kubernetes defaults to
> `IfNotPresent`, so it uses the copy you loaded instead of trying to download it.

### Task 6 - Meet the real runtime: containerd
Kubernetes doesn't use Docker on the nodes. It talks to **containerd** through the Container
Runtime Interface (CRI). `crictl` is the CRI debugging tool:
```bash
NODE=$(kubectl -n lab-containers get pod hello-web -o jsonpath='{.spec.nodeName}')
docker exec -it "$NODE" crictl ps          # containers on that node, as the kubelet sees them
docker exec -it "$NODE" crictl images | grep -E 'hello-web|pause'
```
Notice the `pause` image. Every pod has a tiny "pause" container that holds the pod's network
namespace. Harvester nodes run containerd under RKE2 in the same way, so when you SSH into a
Harvester node later, `crictl` is how you'll look at containers.

## Check your work
```bash
./labctl verify t1-01
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-01
```
You get a ticket: pod `hello-v2` won't start. Diagnose it with `kubectl get`, `describe` and the
events, then fix it. Don't just delete the pod; the ticket asks for v2 to be running.

<details><summary>Hint 1</summary>

`kubectl -n lab-containers describe pod hello-v2`: read the **Events** at the bottom.
What does `ErrImagePull` / `ImagePullBackOff` tell you?
</details>

<details><summary>Hint 2</summary>

The image `hello-web:2.0` doesn't exist anywhere. Change `index.html` so it contains `v2`,
build `hello-web:2.0`, and `kind load` it.
</details>

<details><summary>Hint 3</summary>

Kubernetes retries the pull with exponential **back-off** (up to 5 minutes between attempts).
You can wait, or recreate the pod straight away:
`kubectl delete pod hello-v2 -n lab-containers && kubectl apply -f labs/tier1/01-containers/breakfix/hello-v2.yaml`
</details>

Check: `./labctl breakfix t1-01 --check`

## Cleanup
```bash
./labctl cleanup t1-01
```
This removes the namespace, the images on the kind nodes, the local registry and the
`hello-web` images. Your `work/` files are kept.

## Review questions
1. What is the difference between an image and a container? Which one is read-only?
2. `busybox:1.37`: what is the full reference, including the registry?
3. Why is pinning by digest safer than pinning by tag? What threat does it prevent?
4. Why couldn't the kind nodes see `hello-web:1.0` until you ran `kind load`? How would a real
   cluster, such as Harvester, get the image instead?
5. What is the `pause` container for?
6. Which component on a Kubernetes node plays the role AHV plays on a Nutanix node?
7. Why is `USER 65534` in the Dockerfile a security improvement? What could root inside a
   container do if it escaped?
