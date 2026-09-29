# CLAUDE.md - project context for future sessions

## What this repo is
A study-and-lab toolkit that takes the user from container/Kubernetes fundamentals to planning
and running a **production VMware vSphere → SUSE Virtualization (Harvester) migration** with the
**vm-import-controller** add-on. It has four parts:
- a Markdown curriculum
- tiered labs, each with setup/verify/breakfix/cleanup scripts, a README and review questions
- a bash CLI, `labctl`
- flashcard quizzes

A generic migration runbook template is still to come.

## The learner
- New role involving Kubernetes, containers and Harvester. The first big task is migrating VMs
  from production vSphere to Harvester.
- Background: **Nutanix AHV/Prism**, which is the primary analogy for every concept. Also Citrix
  VDI, Windows/AD and some GCP. Security background (Security+, CySA+), so security framing
  lands well.
- **No** hands-on VMware or Kubernetes experience. Linux/CLI: beginner to intermediate.
- Lab machine: Windows 11 Pro, i9-12900K (16C/24T), **32 GB RAM (upgrade not possible)**, 4 TB
  NVMe + 2x ~1 TB SATA SSD. WSL2 is enabled, with Ubuntu and a docker-desktop distro. Hyper-V
  feature **disabled**. VBS is running, so the Windows hypervisor is active (which explains why
  `VirtualizationFirmwareEnabled` reads False). Windows has docker + kubectl from Docker Desktop.
  No kind/k3d/helm/git on Windows.

## Decisions made with the user (2026-09-29)
1. **Tier 3 = option B:** nested single-node Harvester at about 24 GB RAM, which is **below** the
   32 GB dev/test minimum. It's officially unsupported ("laptops and nested virtualization are
   not supported"), and the user has been told it'll be slow and fragile. Still to verify before
   building Tier 3:
   - does the installer hard-block or only warn below the minimum?
   - Hyper-V must be enabled (Win11 Pro) with `ExposeVirtualizationExtensions`, and the Gen2 VM
     must be UEFI-only for new installs from v1.8.0
   - single-node needs a 1-replica StorageClass, because the default `harvester-longhorn` has 3
     replicas and volumes would show as Degraded
2. **Target Harvester v1.9.0** (the default; the work cluster's version is unknown).
3. **Plain Docker Engine inside WSL2 Ubuntu**, not Docker Desktop. See docs/setup-windows-wsl2.md.
4. Rancher at work: *probably* used, not confirmed. Windows VMs in scope: *probably not*, not
   confirmed. Build Tier 4d anyway, but keep it concise.
5. Push to branch `claude/brave-curie-14lvqp`.

## Rules from the user (always follow)
- Verify against current official docs (Harvester, KubeVirt, Kubernetes, Longhorn) before
  writing. Pin versions. Link the doc page each lab is based on. State the targeted Harvester
  version when behaviour differs.
- **Teach, don't just automate:** every script step prints a short "why", and the user types the
  key commands from the README. Setup scripts only prepare the environment.
- Scripts are idempotent with clean teardown.
- Never hardcode real credentials. Use placeholders plus `.env.example`. The runbook must be
  generic (no real hostnames, IPs or credentials).
- Build incrementally: get each tier fully working and verified end to end before moving on.

## Pinned versions (see versions.env)
- kind v0.33.0 (sha256-pinned); node image `kindest/node:v1.36.4@sha256:099e0493…`; kubectl
  v1.36.5 (sha256-pinned)
- Lab images: nginx:1.29-alpine / 1.30-alpine, busybox:1.37, curlimages/curl:8.16.0, registry:3
- Harvester v1.9.0 bundles, read from the v1.9.0 git tag: RKE2 v1.36.3+rke2r1, KubeVirt 1.8.4
  (SUSE build 1.8.4-9.1), CDI 1.65.0, Longhorn 1.12.1, embedded Rancher v2.15.0. v1.9.1 was at
  the RC stage on 2026-09-29.

## Repo layout and conventions
- `labctl` (bash) → `lib/common.sh` (helpers: `k`, `step`, `check`, `hint`, `load_images`,
  `ensure_ns`...), `lib/cluster.sh`, and `lib/labctl_py.py` (progress + quizzes, stdlib only).
  Progress is in `.labctl/progress.json` (git-ignored).
- Labs live in `labs/tierN/NN-name/` with `lab.env` (LAB_ID, LAB_TITLE, LAB_NAMESPACE),
  `setup.sh`, `verify.sh`, `breakfix.sh inject|check`, `cleanup.sh`, `README.md`, and
  optionally `manifests/` and `breakfix/`. `work/` is git-ignored scratch space for the user.
- Every kubectl call uses `--context kind-k8slab` (the `k` helper), so scripts never touch other
  clusters.
- Lab README structure: objectives → Nutanix mapping box → "Based on (official docs)" → setup →
  tasks with *why* → verify → break/fix with 2-3 collapsed hints → cleanup → review questions.
- Quizzes: `quizzes/NN-*.md`, where each card is `### Q:` followed by `**A:**`.
- `tests/e2e-tier1.sh` holds the **solutions**. It runs every lab through setup x2 → solve →
  verify → breakfix → fix → check → cleanup x2. Run `FRESH=1 tests/e2e-tier1.sh` after any
  version bump. It must pass before pushing lab changes.
- Lint with `shellcheck -x labctl lib/*.sh labs/*/*/*.sh tests/*.sh` (`.shellcheckrc` disables
  SC1091/SC2015).

## Gotchas discovered while building (keep these in mind)
- **Docker 29 + `kind load docker-image`** fails for pulled multi-arch images ("content digest
  … not found"). `load_images` uses `docker save --platform linux/<arch>` + `kind load
  image-archive`. Locally built single-platform images are fine with `kind load docker-image`.
- **cgroup v1 hosts:** Kubernetes ≥1.35 kubelet refuses to start. `lib/cluster.sh` detects this
  and adds `failCgroupV1: false`. Hosts missing CAP_SYS_RESOURCE (the cloud build sandbox) also
  need containerd `restrict_oom_score_adj` + kube-proxy `oomScoreAdj: 0`, likewise
  auto-detected. The user's WSL2 should need neither.
- **kindnet NetworkPolicy** enforcement needs kernel nftables features. It was NOT enforced in
  the build sandbox. t1-04 verify grades the policy objects and only *reports* enforcement.
- In the build sandbox, pods inside kind can't pull images through the proxy, so labs always
  preload images (which also helps the user with Docker Hub rate limits).
- The docs sites (docs.harvesterhci.io, kubernetes.io, kind.sigs.k8s.io, docs.docker.com) were
  blocked from the build sandbox. They were verified through their GitHub sources instead:
  harvester/docs `versioned_docs/version-v1.9`, kubernetes/website, kubernetes-sigs/kind
  site/content, docker/docs, MicrosoftDocs/WSL.
- `kubectl --token` also sends the kubeconfig client cert, so use `--kubeconfig=/dev/null`
  (t1-07).
- busybox `sleep` as PID 1 ignores SIGTERM, so pods take 30 s to terminate and still count
  against quota (t1-05).

## Progress
| Item | Status |
|---|---|
| Machine inspection + hardware verdict | ✅ done (nested Harvester below minimum; user chose option B) |
| Repo skeleton, labctl, setup guide | ✅ |
| Curriculum 00 (Nutanix map), 01 (containers), 02a-g (Kubernetes core) | ✅ |
| Tier 1 labs t1-01 … t1-09 | ✅ built; every lab verified end to end in the build sandbox (tests/e2e-tier1.sh) |
| Quizzes 00, 01, 02 | ✅ |
| User has run Tier 1 on their own PC | ⏳ not yet. Ask how it went, and what broke on real WSL2 |
| Curriculum 03 KubeVirt + Tier 2 labs | ⏳ next (kind + KubeVirt with /dev/kvm from WSL2 nested virt; emulation fallback; match KubeVirt 1.8.x / CDI 1.65 to Harvester v1.9.0) |
| Curriculum 04 Harvester + Tier 3 (nested, option B) | ⏳ |
| Curriculum 05 VMware concepts | ⏳ |
| Curriculum 06 migration + Tier 4 a-d (OVA, vcsim, failure scenarios, Windows) | ⏳ (vm-import-controller docs: harvester/docs versioned_docs/version-v1.9/advanced/addons/vmimport.md) |
| Migration runbook template | ⏳ (runbook/README.md is a placeholder) |

Update this table and the "Decisions" section whenever a tier is finished or the user answers
an open question.
