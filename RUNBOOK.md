# Kubernetes cluster via Kubespray — 2 node build

Built 2026-08-25. Every command below was actually run, in this order.

## Topology

| Role | Hostname | IP | Groups |
|---|---|---|---|
| Ansible control node | (this box) | 192.168.56.133 | — |
| Control plane + etcd + worker | `k8s-cp-0` | 192.168.56.134 | `kube_control_plane`, `etcd`, `kube_node` |
| Worker | `k8s-w-0` | 192.168.56.135 | `kube_node` |

Both nodes: Ubuntu 26.04 LTS, 4 vCPU, 7.4 GB / 5.4 GB RAM, ~82 GB free, `root` login via SSH key.

## Versions

| Component | Version |
|---|---|
| Kubespray | v2.31.0 (tag) |
| Kubernetes | v1.35.4 |
| etcd | 3.6.10 |
| containerd | 2.2.3 |
| Calico | 3.31.5 |
| Ansible | 11.13.0 (ansible-core 2.18.19) |

Network: Calico, `kube_proxy_mode: ipvs`, services `10.233.0.0/18`, pods `10.233.64.0/18`.

---

## 1. Prerequisites on the Ansible control node

```bash
sudo apt-get install -y python3.14-venv python3-pip sshpass
```

## 2. Clone Kubespray and pin a release

```bash
cd /home/claude/Desktop/kubespray
git clone https://github.com/kubernetes-sigs/kubespray.git .
git checkout v2.31.0
```

Always deploy from a release tag, not `master`.

## 3. Python venv + dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt
```

## 4. SSH access to the nodes

The control node's `~/.ssh/id_ed25519` key was already authorized for `root` on both
nodes. To (re)install it:

```bash
./ops/00-bootstrap-ssh.sh <user> <password>
```

Verify:

```bash
ssh root@192.168.56.134 hostname
ssh root@192.168.56.135 hostname
```

## 5. Firewall

Kubespray does not manage firewalls and expects them off. `ufw` was active on both
nodes and was disabled:

```bash
for n in 192.168.56.134 192.168.56.135; do
  ssh root@$n 'ufw --force disable; systemctl disable --now ufw'
done
```

## 6. Inventory

```bash
cp -rfp inventory/sample inventory/mycluster
```

`inventory/mycluster/inventory.ini`:

```ini
[all]
k8s-cp-0 ansible_host=192.168.56.134 ip=192.168.56.134 etcd_member_name=etcd1
k8s-w-0  ansible_host=192.168.56.135 ip=192.168.56.135

[kube_control_plane]
k8s-cp-0

[etcd:children]
kube_control_plane

[kube_node]
k8s-cp-0
k8s-w-0

[k8s_cluster:children]
kube_control_plane
kube_node
```

Two deliberate choices:

- **Inventory names match the real hostnames.** Kubespray sets each node's hostname
  from `inventory_hostname`; using `node1`/`node2` would have renamed the machines.
- **`k8s-cp-0` is listed under `kube_node`.** That is what makes the control plane
  schedulable — kubespray removes the `node-role.kubernetes.io/control-plane:NoSchedule`
  taint for any host in `kube_node`
  (`roles/kubernetes/control-plane/tasks/kubeadm-setup.yml`). No extra variable needed.

`inventory/mycluster/group_vars/all/ansible.yml`:

```yaml
---
ansible_user: root
ansible_python_interpreter: /usr/bin/python3
```

## 7. Connectivity check

```bash
ansible -i inventory/mycluster/inventory.ini all -m ping
```

## 8. Deploy

```bash
ansible-playbook -i inventory/mycluster/inventory.ini \
    --become --become-user=root cluster.yml
```

Or `./ops/01-deploy.sh`. Took **25m 32s**; almost all of it was artifact downloads
(three single downloads accounted for ~8.5 min).

Result: `k8s-cp-0 ok=639 changed=136 failed=0`, `k8s-w-0 ok=439 changed=87 failed=0`.

## 9. Post-deploy fix — CoreDNS CrashLoopBackOff

> Full root-cause analysis, including how it was diagnosed step by step:
> [`COREDNS-LOOP-RCA.md`](COREDNS-LOOP-RCA.md)

**Both CoreDNS replicas crashlooped immediately after deploy:**

```
[FATAL] plugin/loop: Loop (127.0.0.1:46967 -> :53) detected for zone "."
```

**Cause.** `/etc/resolv.conf` on both nodes is a static file containing only
`nameserver 127.0.0.53`, the systemd-resolved stub. CoreDNS inherits that as its
upstream, so queries went:

```
pod -> CoreDNS -> 127.0.0.53 (stub) -> 169.254.25.10 (nodelocaldns) -> CoreDNS
```

— a loop, which CoreDNS detects and exits on.

**Fix.** Give CoreDNS a real upstream. In
`inventory/mycluster/group_vars/all/all.yml`:

```yaml
upstream_dns_servers:
  - 192.168.56.2      # lab gateway/resolver
  - 8.8.8.8           # fallback
disable_host_nameservers: true
```

Re-run only the DNS tasks, then restart CoreDNS:

```bash
ansible-playbook -i inventory/mycluster/inventory.ini --become --become-user=root \
    cluster.yml --tags resolvconf,coredns,nodelocaldns,dnsmasq

ssh root@192.168.56.134 'kubectl delete pod -n kube-system -l k8s-app=kube-dns'
```

Corefile now reads `forward . 192.168.56.2 8.8.8.8`, and both replicas run 1/1.

## 10. kubeconfig on the control node

```bash
./ops/02-fetch-kubeconfig.sh
```

Copies `/etc/kubernetes/admin.conf` off `k8s-cp-0` and rewrites the server URL from
`127.0.0.1:6443` to `192.168.56.134:6443`.

## 11. Addons — Helm + metrics-server

In `inventory/mycluster/group_vars/k8s_cluster/addons.yml`:

```yaml
helm_enabled: true
metrics_server_enabled: true
```

`metrics_server_kubelet_insecure_tls: true` is already the role default, which is what
lets metrics-server scrape kubelets that use self-signed certs.

```bash
ansible-playbook -i inventory/mycluster/inventory.ini --become --become-user=root \
    cluster.yml --tags apps,helm,metrics_server,download
```

4m 32s, `failed=0`. Verify:

```bash
helm version --short                                   # on k8s-cp-0 -> v3.18.4
kubectl get apiservice v1beta1.metrics.k8s.io          # -> True / Passed
kubectl top nodes
```

```
NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-cp-0   182m         5%       2047Mi          31%
k8s-w-0    95m          2%       1082Mi          23%
```

Note: the metrics APIService reports `MissingEndpoints`, then `FailedDiscoveryCheck`,
for ~1-2 min after rollout while the aggregation layer completes its discovery probe.
That is normal; wait before treating it as a fault.

---

## Verification performed

```
NAME       STATUS   ROLES           VERSION   INTERNAL-IP      CONTAINER-RUNTIME
k8s-cp-0   Ready    control-plane   v1.35.4   192.168.56.134   containerd://2.2.3
k8s-w-0    Ready    <none>          v1.35.4   192.168.56.135   containerd://2.2.3
```

- 14/14 pods Running; `/healthz` ok; `livez check passed`
- Taints on both nodes: `<none>` (control plane schedulable, as intended)
- Test deployment spread across both nodes via topology spread constraint
- Internal DNS (`kubernetes.default`) — resolved
- Service DNS (`web.smoke.svc.cluster.local`) — resolved
- External DNS (`github.com`) — resolved
- Cross-node pod-to-pod over Calico — reached
- Service VIP load-balancing — 6 requests split 3/3 across nodes

---

## Operations

```bash
source .venv/bin/activate

kubectl get nodes                  # from control node, kubeconfig already in place
./ops/01-deploy.sh                 # re-run / converge (idempotent)
./ops/02-fetch-kubeconfig.sh       # refresh kubeconfig
./ops/99-reset.sh                  # DESTRUCTIVE: tear cluster back to bare nodes
```

Add a node: add it to `[kube_node]`, then
`ansible-playbook -i inventory/mycluster/inventory.ini --become scale.yml`.

Upgrade: check out the next kubespray tag, then `upgrade-cluster.yml`. Do not skip
minor releases.

## Caveats

- **Ubuntu 26.04 is not on kubespray's supported list** (v2.31.0 and master list only
  22.04/24.04). It works here — the version-gated tasks are all in the `docker` role,
  unused since `container_manager: containerd` pulls upstream binaries — but this is
  untested upstream and is the first suspect for any future breakage.
- `ufw` is disabled on both nodes. Re-enabling it requires opening at minimum 6443,
  2379-2380, 10250-10259, 179, and 4789/udp.
- Single control plane — no HA. Losing `k8s-cp-0` loses the cluster.
- Helm and metrics-server are enabled (see section 11). Other addons are off; toggle
  them in `inventory/mycluster/group_vars/k8s_cluster/addons.yml`
  (`local_path_provisioner_enabled`, `ingress_nginx_enabled`, …) and re-run
  `cluster.yml`.

## Files added to this repo

```
ops/00-bootstrap-ssh.sh        install SSH key + passwordless sudo
ops/01-deploy.sh               run cluster.yml
ops/02-fetch-kubeconfig.sh     pull admin.conf, rewrite server URL
ops/99-reset.sh                run reset.yml (destructive)
logs/deploy.log                full deploy transcript
logs/dnsfix.log                DNS remediation transcript
logs/addons.log                helm + metrics-server transcript
COREDNS-LOOP-RCA.md            CoreDNS loop root-cause analysis
inventory/mycluster/           inventory + group_vars (gitignored upstream)
RUNBOOK.md                     this file
```
