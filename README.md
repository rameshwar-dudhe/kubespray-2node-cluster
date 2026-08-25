# 2-node Kubernetes cluster with Kubespray

Config, scripts and notes for building a 2-node Kubernetes cluster with
[Kubespray](https://github.com/kubernetes-sigs/kubespray). Built and verified
end-to-end on 2026-08-25, then torn down.

This repo holds **only my own files** — inventory, helper scripts, docs and run logs.
Kubespray itself is not vendored here; you clone it separately (step 1 below).

## Topology

| Role | Hostname | IP |
|---|---|---|
| Ansible control node | — | 192.168.56.133 |
| Control plane + etcd + worker | `k8s-cp-0` | 192.168.56.134 |
| Worker | `k8s-w-0` | 192.168.56.135 |

The control plane is deliberately **schedulable** — it is listed under `kube_node` in
the inventory, which makes kubespray remove the
`node-role.kubernetes.io/control-plane:NoSchedule` taint automatically.

## Versions

| Component | Version |
|---|---|
| Kubespray | v2.31.0 |
| Kubernetes | v1.35.4 |
| etcd | 3.6.10 |
| containerd | 2.2.3 |
| Calico | 3.31.5 |
| Ansible | 11.13.0 (ansible-core 2.18.19) |

Calico CNI, `ipvs` kube-proxy, Helm and metrics-server enabled.

## Docs

| File | What it is |
|---|---|
| [`RUNBOOK.md`](RUNBOOK.md) | Every command in order, start to finish |
| [`COREDNS-LOOP-RCA.md`](COREDNS-LOOP-RCA.md) | Why CoreDNS crashed after install, and how it was fixed — in plain language |

## Usage

```bash
# 1. get kubespray at the matching release
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray && git checkout v2.31.0

# 2. drop this repo's files in
cp -r /path/to/this-repo/inventory/mycluster inventory/
cp -r /path/to/this-repo/ops .

# 3. python deps
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 4. edit inventory/mycluster/inventory.ini for your own IPs, then
./ops/00-bootstrap-ssh.sh <user> <password>   # install SSH keys
./ops/01-deploy.sh                            # build the cluster (~25 min)
./ops/02-fetch-kubeconfig.sh                  # get kubeconfig locally
./ops/99-reset.sh                             # tear it all down
```

## Logs

`logs/` holds the raw Ansible output from the real runs — useful as a reference for
what a healthy run looks like and how long each phase takes.

| Log | Run | Result |
|---|---|---|
| `deploy.log` | initial `cluster.yml` | 25m 32s, `failed=0` |
| `dnsfix.log` | CoreDNS loop fix | 54s, `failed=0` |
| `addons.log` | Helm + metrics-server | 4m 32s, `failed=0` |
| `reset.log` | teardown | 2m 42s, `failed=0` |

## Notes and caveats

- **Ubuntu 26.04 is not on kubespray's supported list** (v2.31.0 supports 22.04/24.04).
  It worked here — the version-gated tasks live in the unused `docker` role, since
  `container_manager: containerd` installs upstream binaries — but it is untested
  upstream.
- **`ufw` was disabled** on both nodes. Kubespray does not manage firewalls and
  expects them off.
- **Single control plane, no HA.** Fine for a lab, not for production.
- **A successful Ansible run is not a healthy cluster.** This deploy exited `0` with
  `failed=0` while DNS was completely broken. Always verify with
  `kubectl get pods -A`. See `COREDNS-LOOP-RCA.md`.
- Generated credentials (`inventory/*/credentials/`) are gitignored and never
  committed.
