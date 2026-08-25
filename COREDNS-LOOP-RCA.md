# CoreDNS was crashing — what happened and how I fixed it

Cluster: kubespray v2.31.0, Kubernetes v1.35.4, Ubuntu 26.04.
Nodes: `k8s-cp-0` (192.168.56.134), `k8s-w-0` (192.168.56.135). Date: 2026-08-25.

**Short version:** CoreDNS was asking a DNS server that sent the question right back
to CoreDNS. The question went in a circle forever. CoreDNS noticed this and shut
itself down.

---

## 1. First, some background

**What is CoreDNS?** It is the phone book of the cluster. When one pod wants to talk
to another by name, it asks CoreDNS "what is the IP address of this name?"

**What CoreDNS does when it doesn't know:** For names inside the cluster it answers
itself. For outside names like `github.com`, it does not know the answer, so it passes
the question to another DNS server. That other server is called the **upstream**.

**Where does it get the upstream from?** From a file on the node called
`/etc/resolv.conf`. Whatever DNS server is written in that file, CoreDNS uses it.

That last point is the whole story. Keep it in mind.

---

## 2. What went wrong

The install command finished and said everything was fine:

```
failed=0    exit code 0
```

But when I actually looked at the cluster, CoreDNS was broken:

```bash
kubectl get pods -A
```

```
kube-system   coredns-58cc5d8ddf-6cmfd   0/1   CrashLoopBackOff   3 (18s ago)
kube-system   coredns-58cc5d8ddf-78szm   0/1   CrashLoopBackOff   3 (11s ago)
```

`CrashLoopBackOff` means the container starts, dies, and Kubernetes keeps restarting
it. Both copies of CoreDNS were doing this. Everything else was fine.

> **Important:** the install said "success" but the cluster was broken. A green
> Ansible run does not mean a healthy cluster. Always check with
> `kubectl get pods -A` afterwards.

---

## 3. How I found the cause

### Step 1 — I read the logs

This is always the first thing to do. A crashing program usually tells you why it
crashed.

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=30
```

```
CoreDNS-1.12.4
[FATAL] plugin/loop: Loop (127.0.0.1:46967 -> :53) detected for zone ".",
        see https://coredns.io/plugins/loop#troubleshooting.
```

CoreDNS said it plainly: it found a **loop**.

### Step 2 — I checked how it died

I wanted to know if CoreDNS chose to quit, or if something killed it. These are very
different problems.

```
exit=1   reason=Error
```

`exit=1` means CoreDNS decided to stop on its own. If it had said `OOMKilled` or
`exit=137`, that would mean it ran out of memory — a completely different fix. So the
loop message was the real cause.

### Step 3 — I checked the DNS settings on the nodes

Remember: CoreDNS reads its upstream from `/etc/resolv.conf`. So I looked at that file
on both nodes.

```bash
ssh root@192.168.56.134 'cat /etc/resolv.conf; ls -l /etc/resolv.conf; resolvectl status'
```

```
nameserver 127.0.0.53                                  <-- point A
-rw-r--r-- 1 root root 930 Aug 11 15:13 /etc/resolv.conf   <-- point B
Current DNS Server: 169.254.25.10                      <-- point C
Current DNS Server: 192.168.56.2
```

Three things stood out:

**Point A —** The only DNS server listed is `127.0.0.53`. Addresses starting with
`127.` mean "this same machine". So this is not a real outside DNS server. It is a
small local helper program on the node called *systemd-resolved*.

**Point B —** The date is `Aug 11`, which is before I installed anything. So this is an
old file that kubespray never touched.

**Point C —** That local helper program sends its questions to `169.254.25.10`. That
address is **nodelocaldns**, a small DNS cache that kubespray installs on every node.
And nodelocaldns sends cluster questions to CoreDNS.

---

## 4. The actual problem

Now put those three points together:

```
   pod asks a question
        |
        v
   CoreDNS               reads /etc/resolv.conf, sees 127.0.0.53
        |
        v
   127.0.0.53            the local helper on the node
        |
        v
   169.254.25.10         nodelocaldns
        |
        v
   CoreDNS               <-- back to where we started
```

The question goes in a circle. It never reaches a real DNS server.

**An everyday example:** You ask your friend for someone's phone number. He doesn't
know it, so he asks his neighbour. The neighbour doesn't know either, so he asks your
friend. Now the same question keeps bouncing between two people forever. Nobody ever
gets an answer.

That is exactly what was happening here.

**How CoreDNS catches this:** When CoreDNS starts, it sends itself one test question
(you can see it in the log as `HINFO` with random numbers). If that test question
comes back to itself, CoreDNS knows the setup is circular. It then shuts down on
purpose, instead of running in circles forever and freezing the machine.

**Why it happened on these nodes:** Ubuntu does not usually write a real DNS server
into `/etc/resolv.conf`. It writes `127.0.0.53` and lets the local helper program deal
with it. On top of that, kubespray told that helper to use nodelocaldns. And because
`/etc/resolv.conf` was an old fixed file, nothing ever corrected it. So CoreDNS was
handed a path that led straight back to itself.

This is a well known CoreDNS problem. It is documented at
<https://coredns.io/plugins/loop#troubleshooting>.

---

## 5. The fix

The fix is simple: **tell CoreDNS to use a real DNS server**, instead of letting it
copy whatever is in `/etc/resolv.conf`.

Kubespray has a setting for exactly this. I added it to
`inventory/mycluster/group_vars/all/all.yml`:

```yaml
upstream_dns_servers:
  - 192.168.56.2      # the real DNS server on your network
  - 8.8.8.8           # Google DNS, as a backup

disable_host_nameservers: true   # do not copy 127.0.0.53 from the node
```

Where did `192.168.56.2` come from? It was in the `resolvectl status` output in Step 3
— that is the real DNS server your network uses.

Then I re-ran only the DNS part of the install, instead of the whole thing:

```bash
ansible-playbook -i inventory/mycluster/inventory.ini --become --become-user=root \
    cluster.yml --tags resolvconf,coredns,nodelocaldns,dnsmasq
```

This took 54 seconds. Then I deleted the CoreDNS pods so new ones would start with the
new settings:

```bash
kubectl delete pod -n kube-system -l k8s-app=kube-dns
```

This delete step is needed. Changing the setting alone does not restart CoreDNS.

### Why I did not fix it the other ways

| What I could have done | Why I did not |
|---|---|
| Edit `/etc/resolv.conf` on each node by hand | Kubespray would overwrite it next time you run the install, and a reboot could undo it too. You would also have to repeat it on every node. |
| Edit the CoreDNS settings in Kubernetes directly | Same problem — kubespray replaces it on the next run. |
| Turn off systemd-resolved completely | Too risky. If it goes wrong, the node cannot look up any names at all. |

**The rule to remember:** change the setting in the kubespray inventory files, not on
the node itself. Anything you type directly on a node will be wiped the next time
kubespray runs.

---

## 6. Checking that it worked

First, that CoreDNS now points at a real DNS server:

```bash
kubectl get cm -n kube-system coredns -o jsonpath="{.data.Corefile}" | grep forward
```

```
forward . 192.168.56.2 8.8.8.8
```

Good — `127.0.0.53` is gone.

Then, that the pods are healthy:

```
coredns-5f8878f58-nbhc6   1/1   Running   0 restarts
coredns-5f8878f58-qlx2s   1/1   Running   0 restarts
```

`1/1 Running` with **0 restarts** — no more crashing.

Then I tested real lookups from inside a pod:

| What I tested | Result |
|---|---|
| A name inside the cluster (`kubernetes.default`) | works — `10.233.0.1` |
| A service name (`web.smoke.svc`) | works — `10.233.48.250` |
| **An outside name (`github.com`)** | works — `20.207.73.82` |
| One pod talking to a pod on the other node | works |
| A service sharing traffic between both nodes | works — 3 requests each |

The `github.com` test is the important one. That lookup had to go to an outside DNS
server, so it could never have worked while the loop existed. It working proves the
problem is really gone.

---

## 7. If CoreDNS crashes again

1. Look at the pods:
   `kubectl get pods -n kube-system -l k8s-app=kube-dns`
2. **Read the logs first.** CoreDNS almost always tells you the reason:
   `kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50`
3. Match the message to the cause:

   | Message in the log | What it means |
   |---|---|
   | `plugin/loop: Loop ... detected` | The circle problem in this document. |
   | `address already in use` | Something else is already using port 53. Set `systemd_resolved_disable_stub_listener: true`. |
   | `OOMKilled` or `exit=137` | Out of memory. Give it a higher memory limit. |
   | `no route to host`, timeouts | Not a DNS problem. Check the firewall or the network plugin. |

4. If it is the loop problem, check `/etc/resolv.conf` on **every** node.
5. **Any address starting with `127.` in `/etc/resolv.conf` on a Kubernetes node is a
   warning sign.**
6. Fix it in the inventory file, re-run the DNS tags, delete the pods.
7. Always test with an outside name like `github.com`, not just a cluster name.

---

## Words used in this document

| Word | Meaning |
|---|---|
| CoreDNS | The DNS server inside the cluster. The cluster's phone book. |
| nodelocaldns | A small DNS cache kubespray puts on every node to make lookups faster. |
| upstream DNS | The DNS server you ask when you do not know the answer yourself. |
| `/etc/resolv.conf` | The file on a Linux machine that lists which DNS servers to use. |
| systemd-resolved | Ubuntu's built-in DNS helper program. It listens on `127.0.0.53`. |
| CrashLoopBackOff | Kubernetes-speak for "this container keeps starting and dying". |
| Corefile | CoreDNS's configuration. Stored in Kubernetes as a ConfigMap. |
| inventory | The kubespray folder holding your cluster's settings. Here: `inventory/mycluster/`. |
