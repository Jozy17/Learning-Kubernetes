# Lab t1-09: kubectl fluency: find, filter, format, change

**Curriculum:** [02a - Architecture & kubectl](../../../curriculum/02-kubernetes-core/02a-architecture-kubectl.md) · **Time:** ~60 min

## Objectives
1. Set up kubectl for speed: an alias, shell completion, and contexts and namespaces.
2. **Find** things with label selectors and field selectors.
3. **Format** output with `-o wide`, `custom-columns`, `jsonpath` and `--sort-by`.
4. **Change** things safely with `--dry-run=client -o yaml`, `diff`, `apply`, `scale`, `patch`,
   `label` and `annotate`.
5. Know where you are: contexts, clusters and default namespaces.

> **Nutanix mapping:** kubectl is your `ncli` / `acli` plus the Prism REST API in one tool.
> Every kubectl command is an HTTPS call to the API server. Run any command with `-v=6` to see
> the URLs it calls. What `acli vm.list` is to AHV, `kubectl get vm` will be to Harvester.

## Based on (official docs)
- kubectl quick reference - <https://kubernetes.io/docs/reference/kubectl/quick-reference/>
- JSONPath support - <https://kubernetes.io/docs/reference/kubectl/jsonpath/>
- Labels and selectors - <https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/>
- Field selectors - <https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/>
- Organizing access with kubeconfig - <https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/>
- Declarative management (apply/diff) - <https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/>

## Setup
```bash
./labctl start t1-09
```
Setup deploys an "estate" of four Deployments and two batch pods into `lab-kubectl`. Don't read
`manifests/estate.yaml` first, because finding things with kubectl is the exercise.

---

## Tasks

### Task 1 - Set up your shell (do this once, and keep it)
```bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
k get no<TAB>        # completes to "nodes"
```

### Task 2 - Where am I?
```bash
kubectl config get-contexts        # * marks the current context; note the NAMESPACE column
kubectl config current-context
kubectl cluster-info
kubectl get nodes -v=6 2>&1 | grep -m2 GET      # the raw API calls behind the command
```
**Why this matters:** at work you'll have several contexts, such as the lab, a staging Harvester
and a production Harvester. Before any destructive command, check which context you're in.

### Task 3 - Find the failed pod and label it
```bash
kubectl -n lab-kubectl get pods --show-labels
kubectl -n lab-kubectl get pods -l tier=batch                         # label selector
kubectl -n lab-kubectl get pods --field-selector=status.phase=Failed  # field selector
kubectl -n lab-kubectl logs nightly-export-7f3kq                       # why did it fail?
kubectl -n lab-kubectl label pod nightly-export-7f3kq triage=needed
kubectl -n lab-kubectl get pods -l triage=needed
```
**Labels vs fields:** you set labels yourself, as arbitrary tags you can select on, much like
Nutanix *categories*. Fields are built-in object properties, and only some of them are
selectable.

### Task 4 - Which Deployment runs an old image?
```bash
kubectl -n lab-kubectl get deploy -o wide                  # IMAGES column
kubectl -n lab-kubectl get deploy -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,REPLICAS:.spec.replicas
kubectl -n lab-kubectl get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```
One of them is on `nginx:1.29-alpine`. Mark it for the next patch window:
```bash
kubectl -n lab-kubectl annotate deployment <name> upgrade=pending
```
**Labels vs annotations:** labels are for *selecting*. Annotations are for *information*, such as
tickets, change causes and tool metadata, and you can't select on them.

### Task 5 - Generate, edit, diff, apply
```bash
cd labs/tier1/09-kubectl-fluency/work
kubectl -n lab-kubectl create deployment report --image=nginx:1.30-alpine --replicas=2 \
  --dry-run=client -o yaml > report.yaml
```
Edit `report.yaml`: under `metadata.labels`, add `team: ops`. Also delete the empty
`status: {}` / `strategy: {}` / `resources: {}` lines (and `creationTimestamp: null` if your
kubectl adds it). They're harmless noise, but get used to keeping manifests clean.
```bash
kubectl apply -f report.yaml
```
Now change `replicas: 2` to `replicas: 3` in the file, and **preview** the change before
applying it:
```bash
kubectl diff -f report.yaml        # shows exactly what would change on the live object
kubectl apply -f report.yaml
```
`kubectl diff` is your change-review habit. Use it before every apply on a real cluster.

### Task 6 - Act on many objects with one selector
```bash
kubectl -n lab-kubectl get deploy -l tier=cache
kubectl -n lab-kubectl scale deployment -l tier=cache --replicas=2
```

### Task 7 - Patch a single field
```bash
kubectl -n lab-kubectl get deploy backend -o jsonpath='{.spec.revisionHistoryLimit}{"\n"}'   # default 10
kubectl -n lab-kubectl patch deployment backend --type=merge -p '{"spec":{"revisionHistoryLimit":3}}'
```
`patch` is great in scripts. For anything you'll maintain over time, prefer changing the file and
running `apply`.

### Task 8 - Output drills (not graded, but do them)
```bash
kubectl -n lab-kubectl get pods -o wide --sort-by=.spec.nodeName          # group by node
kubectl -n lab-kubectl get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase
kubectl -n lab-kubectl get events --sort-by=.lastTimestamp | tail -10     # recent history
kubectl get pods -A -o wide | awk 'NR>1{print $8}' | sort | uniq -c        # pods per node, all namespaces
kubectl explain deployment.spec.strategy.rollingUpdate                      # built-in docs
kubectl -n lab-kubectl get deploy frontend -o yaml | less                   # read a full object
kubectl -n lab-kubectl get pods -w                                          # watch (Ctrl+C)
```

## Check your work
```bash
./labctl verify t1-09
```

---

## Break/fix scenario
```bash
./labctl breakfix t1-09
```
Suddenly "the cluster is empty". **This one changes your kubeconfig** (the lab context only).
`./labctl cleanup t1-09` always puts it back.

<details><summary>Hint 1</summary>

Nothing was deleted: `kubectl get deploy -A` still shows everything. So why does plain
`kubectl get deploy` show nothing? Run `kubectl config get-contexts`.
</details>

<details><summary>Hint 2</summary>

The context's default namespace was set to `lab-kubect1`, ending in the digit **one**, which
doesn't exist. Fix it:
`kubectl config set-context --current --namespace=lab-kubectl`
(or `kubectl config unset contexts.kind-k8slab.namespace` to go back to `default`).
</details>

**Lesson:** a lot of "disaster" reports are "wrong context or namespace". Tools such as
`kubens` / `kubectx`, or a shell prompt that shows the current context, help prevent this.

Check: `./labctl breakfix t1-09 --check`

## Cleanup
```bash
./labctl cleanup t1-09
```

## Review questions
1. What's the difference between a label and an annotation? Give one use for each.
2. Write the command that lists only pods in phase `Failed` across all namespaces.
3. Write a `custom-columns` command that shows each pod's name and node.
4. Why use `kubectl diff` before `kubectl apply`?
5. When would you use `patch` rather than editing a file and running `apply`?
6. `kubectl get pods` says "No resources found", but the app is running. Name three possible
   reasons.
7. How do you check which cluster and namespace kubectl will act on before a destructive
   command?
