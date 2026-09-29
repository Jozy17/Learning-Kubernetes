# Learning Kubernetes → KubeVirt → Harvester → VMware migration

A hands-on study and lab toolkit that goes from container basics to planning and running a
**VMware vSphere → SUSE Virtualization (Harvester)** migration with the
**vm-import-controller** add-on. It's written for an engineer coming from **Nutanix
(AHV/Prism)**, so concepts are explained by mapping them to Nutanix equivalents.

- **Target platform:** Harvester **v1.9.0** (Kubernetes v1.36 / RKE2, KubeVirt 1.8, Longhorn
  1.12). All pins are in [`versions.env`](versions.env).
- **Lab machine:** Windows 11 + WSL2 (Ubuntu) + Docker Engine. See
  [docs/setup-windows-wsl2.md](docs/setup-windows-wsl2.md).

## Quick start
```bash
./labctl doctor          # check the machine
./labctl install-tools   # pinned kind + kubectl (checksum-verified) into ~/.local/bin
./labctl cluster up      # 3-node kind cluster "k8slab"
./labctl list            # labs and your status
./labctl start t1-01     # then follow labs/tier1/01-containers/README.md
```

## What's here
| Path | What |
|---|---|
| [`curriculum/`](curriculum/README.md) | Markdown modules. Start with [00 - the Nutanix → Harvester concept map](curriculum/00-orientation-nutanix-map.md) |
| [`labs/`](labs/tier1/README.md) | Tiered labs. Each has a README (objectives, tasks, break/fix, review questions) plus `setup.sh`, `verify.sh`, `breakfix.sh`, `cleanup.sh` |
| [`quizzes/`](quizzes/) | Flashcards per module (`./labctl quiz 02`) |
| [`labctl`](labctl) + [`lib/`](lib/) | The CLI: plain bash plus a small stdlib-only Python helper |
| [`clusters/`](clusters/) | kind cluster definitions |
| [`runbook/`](runbook/) | VMware → Harvester migration runbook template (placeholder, built with Tier 4) |
| [`tests/`](tests/) | End-to-end regression test for the labs (**contains solutions: spoilers!**) |
| [`CLAUDE.md`](CLAUDE.md) | Project context and progress for future AI-assisted sessions |

## Tiers
| Tier | Topic | Runs on | Status |
|---|---|---|---|
| 1 | Kubernetes fundamentals (9 labs) | kind, in WSL2 | ✅ built and verified end to end |
| 2 | KubeVirt on a local cluster | kind/k3d + nested KVM in WSL2 | planned |
| 3 | Harvester, nested single node (~24 GB, **below the 32 GB minimum**) | Hyper-V VM | planned. It will be slow and is officially unsupported; see CLAUDE.md |
| 4 | Migration: OVA import, vcsim `VmwareSource`, failure scenarios, Windows VMs | Tier 3 Harvester | planned |

## How each lab works
1. `./labctl start <lab>` prepares **only** the environment (namespace, images, sample apps) and
   explains each step's *why*.
2. You **type the key commands yourself** from the lab README. That's the point.
3. `./labctl verify <lab>` checks the resulting cluster state and gives hints.
4. `./labctl breakfix <lab>` injects a realistic fault. Diagnose it, then run
   `./labctl breakfix <lab> --check`.
5. `./labctl cleanup <lab>` (or `reset`) tears everything down. All scripts are idempotent.

Safety: every script uses `kubectl --context kind-k8slab`, so it can never touch another cluster
in your kubeconfig. No real credentials exist anywhere in this repo; `.env` is git-ignored, and
[`.env.example`](.env.example) has placeholders only.
