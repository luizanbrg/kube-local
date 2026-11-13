# Phase 2 — Ansible Operating System Preparation

## Objective

The objective of Phase 2 was to use **Ansible to automatically prepare the three Linux machines created during Phase 1** for Kubernetes.

At the beginning of this phase, the environment consisted of three essentially blank Ubuntu virtual machines:

| Node            | Role                                 |
| --------------- | ------------------------------------ |
| `control-plane` | Future Kubernetes control-plane node |
| `worker-1`      | Future Kubernetes worker             |
| `worker-2`      | Future Kubernetes worker             |

Instead of configuring each machine manually, the configuration was implemented as reusable Ansible roles.

The provisioning process is therefore:

```text
Blank Linux VM
      │
      ▼
   common
      │
      ▼
  containerd
      │
      ▼
 kubernetes
      │
      ▼
Kubernetes-ready node
```

At the end of this phase, the machines contain everything required to create the Kubernetes cluster, but **the cluster itself has not yet been initialized**.

Commands such as `kubeadm init`, `kubeadm join`, and the installation of the CNI belong to the following phase.

---

# 1. Ansible structure

The provisioning configuration was separated into reusable Ansible roles.

The resulting structure is approximately:

```text
infrastructure/
└── ansible/
    ├── inventory.ini
    ├── group_vars/
    │   └── all.yml
    │
    ├── playbooks/
    │   └── prepare.yml
    │
    └── roles/
        ├── common/
        │   ├── tasks/
        │   │   └── main.yml
        │   └── handlers/
        │       └── main.yml
        │
        ├── containerd/
        │   ├── tasks/
        │   │   └── main.yml
        │   └── handlers/
        │       └── main.yml
        │
        └── kubernetes/
            └── tasks/
                └── main.yml
```

Each role has a specific responsibility:

```text
common
└── Linux operating-system preparation

containerd
└── Container runtime installation and configuration

kubernetes
└── Kubernetes tools installation
```

This separation makes the provisioning easier to maintain and allows the same roles to eventually be adapted for the AWS environment.

---

# 2. Global Ansible variables

Shared configuration is stored under:

```text
group_vars/all.yml
```

This includes the Kubernetes release used by the project.

For example:

```yaml
kubernetes_version: '1.35'
```

The Kubernetes version is therefore defined in one location rather than duplicated throughout the different roles.

More importantly, Kubernetes is **explicitly pinned to a release line instead of blindly installing the latest available version**.

This makes the infrastructure more predictable and reproducible.

---

# 3. `common` role

The `common` role prepares the underlying Linux operating system.

It is executed on all three Kubernetes nodes.

Its responsibilities include:

- base packages;
- hostname configuration;
- node name resolution;
- time synchronization;
- swap configuration;
- required Linux kernel modules;
- Kubernetes networking kernel parameters.

---

## 3.1 Base packages

The role updates the APT package cache and installs the utilities required by the remaining provisioning process.

These include packages such as:

```text
curl
ca-certificates
gnupg
apt-transport-https
chrony
```

`curl`, CA certificates, and GnuPG are particularly useful when configuring external package repositories.

---

## 3.2 Time synchronization

`chrony` is installed and its service is enabled.

Keeping the clocks synchronized between Kubernetes nodes is important for distributed systems, particularly for:

- logs;
- TLS certificates;
- authentication;
- event timestamps;
- troubleshooting across multiple nodes.

---

# 4. Hostname configuration

The hostname of each virtual machine is configured from its Ansible inventory name.

For example:

```text
inventory hostname     Linux hostname
--------------------------------------
control-plane      →   control-plane
worker-1           →   worker-1
worker-2           →   worker-2
```

This avoids maintaining a second independent list of hostnames.

---

# 5. Node name resolution

The nodes also need to be able to communicate using their hostnames.

For example:

```bash
ping control-plane
```

should work from `worker-1` and `worker-2`.

During the implementation, connectivity using the control-plane IP address worked correctly, while using the hostname initially failed because the workers did not know how to resolve `control-plane`.

The `common` role therefore manages the Kubernetes node entries inside:

```text
/etc/hosts
```

The important point is that these addresses are **not hardcoded inside the role**.

Ansible dynamically generates them using the inventory:

```text
inventory
   │
   ├── control-plane → ansible_host
   ├── worker-1      → ansible_host
   └── worker-2      → ansible_host
            │
            ▼
       /etc/hosts
```

The resulting configuration is equivalent to:

```text
192.168.252.2 control-plane
192.168.252.3 worker-1
192.168.252.4 worker-2
```

for the current local environment.

However, if another developer receives different Multipass addresses, Ansible generates the appropriate entries from their inventory automatically.

This avoids duplicating infrastructure information inside the role.

---

# 6. Swap configuration

Swap is disabled on all Kubernetes nodes.

The role performs two operations:

1. disables currently active swap;
2. prevents configured swap from automatically returning after reboot.

This provides a predictable configuration for the kubelet and the kubeadm-based Kubernetes installation.

The resulting state can be checked with:

```bash
swapon --show
```

No active swap should be reported.

---

# 7. Required kernel modules

Two Linux kernel modules required by the container/Kubernetes environment are configured:

```text
overlay
br_netfilter
```

They are persisted through:

```text
/etc/modules-load.d/k8s.conf
```

and also loaded on the currently running system.

### `overlay`

The `overlay` module provides OverlayFS functionality commonly used by container runtimes to implement layered container filesystems.

### `br_netfilter`

`br_netfilter` allows traffic passing through Linux network bridges to be processed by the Linux netfilter subsystem.

This is important for Kubernetes networking.

---

# 8. Kubernetes networking kernel configuration

The following kernel parameters are configured:

```text
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

The configuration is persisted under:

```text
/etc/sysctl.d/
```

### IP forwarding

The particularly important setting:

```text
net.ipv4.ip_forward = 1
```

allows Linux to forward packets between network interfaces.

Kubernetes nodes need this behavior because they participate in routing network traffic between Pods, nodes, Services, and external networks.

The bridge-related settings allow bridged traffic to interact correctly with Linux packet filtering.

---

# 9. Ansible handlers

Handlers were introduced for operations that only need to run when their associated configuration changes.

For example:

```text
sysctl configuration changed
            │
            ▼
       notify handler
            │
            ▼
      sysctl --system
```

Similarly, containerd can be restarted when its configuration changes.

This contributes to **idempotency**.

Ansible should converge a machine toward a desired state rather than blindly repeating every configuration operation each time the playbook runs.

Therefore:

```bash
ansible-playbook playbooks/prepare.yml
```

can safely be executed multiple times.

After the first successful provisioning, subsequent executions should normally report significantly fewer changes.

---

# 10. `containerd` role

The second role installs and configures the container runtime.

The project uses:

```text
containerd
```

rather than Docker Engine as the Kubernetes node runtime.

The architecture is approximately:

```text
Kubernetes
    │
  kubelet
    │
    │ CRI
    ▼
containerd
    │
   runc
    │
Linux kernel
```

Kubelet communicates with the container runtime through the **Container Runtime Interface (CRI)**.

---

## 10.1 Containerd installation

The role installs containerd and creates its configuration directory:

```text
/etc/containerd/
```

The default containerd configuration is then generated into:

```text
/etc/containerd/config.toml
```

The task is designed so that the configuration is not unnecessarily regenerated every time Ansible executes.

---

## 10.2 Systemd cgroups

Containerd is configured with:

```text
SystemdCgroup = true
```

This ensures that containerd uses systemd for cgroup management.

The configuration becomes conceptually:

```text
systemd
   │
   ├── kubelet
   │
   └── containerd
```

rather than having different cgroup-management mechanisms competing on the same host.

Containerd is then enabled so that it automatically starts with the machine.

---

# 11. `kubernetes` role

The third role installs the Kubernetes node tools.

The role configures the official Kubernetes package repository corresponding to the selected Kubernetes release and installs:

```text
kubeadm
kubelet
kubectl
```

---

## 11.1 `kubeadm`

`kubeadm` is responsible for bootstrapping and managing the Kubernetes cluster.

It will later be used to initialize the control plane:

```bash
kubeadm init
```

and connect the workers:

```bash
kubeadm join ...
```

Those operations are intentionally not performed during Phase 2.

---

## 11.2 `kubelet`

`kubelet` is the Kubernetes agent running on each node.

Once the cluster exists, it is responsible for ensuring that the Pods assigned to the node are actually running.

At this stage, kubelet may restart or report errors because the machine has not yet been initialized or joined to a Kubernetes cluster.

That is expected during Phase 2.

---

## 11.3 `kubectl`

`kubectl` is the command-line client used to communicate with the Kubernetes API.

It is installed on the nodes as part of the Kubernetes tooling.

---

# 12. Kubernetes package version control

The Kubernetes packages are placed on hold after installation.

This prevents a normal system package upgrade from unexpectedly upgrading:

```text
kubeadm
kubelet
kubectl
```

Kubernetes upgrades should be intentional and coordinated rather than occurring as a side effect of:

```bash
apt upgrade
```

---

# 13. Main preparation playbook

All three roles are orchestrated through:

```text
playbooks/prepare.yml
```

Conceptually:

```yaml
---
- name: Prepare Kubernetes nodes
  hosts: kubernetes
  become: true

  roles:
    - common
    - containerd
    - kubernetes
```

This means the entire operating-system preparation can be launched with a single command:

```bash
ansible-playbook playbooks/prepare.yml
```

The roles are executed in dependency order:

```text
common
   ↓
containerd
   ↓
kubernetes
```

---

# 14. Validation

After running the preparation playbook, the environment was validated.

Ansible connectivity:

```bash
ansible all -m ping
```

Inventory:

```bash
ansible-inventory --graph
```

Containerd:

```bash
ansible all -a "systemctl is-active containerd"
```

Kubernetes tooling:

```bash
ansible all -a "kubeadm version"

ansible all -a "kubelet --version"

ansible all -a "kubectl version --client"
```

IP forwarding:

```bash
ansible all -a "sysctl net.ipv4.ip_forward"
```

Expected:

```text
net.ipv4.ip_forward = 1
```

Swap:

```bash
ansible all -a "swapon --show"
```

No active swap should be returned.

Kernel modules:

```bash
ansible all -m shell -a "lsmod | grep -E 'overlay|br_netfilter'"
```

Node hostname resolution:

```bash
ansible worker-1,worker-2 -a "ping -c 1 control-plane"
```

This final test confirms that the workers can resolve and communicate with the control-plane node using its hostname.

---

# 15. Idempotency validation

The complete playbook was executed again after the initial provisioning:

```bash
ansible-playbook playbooks/prepare.yml
```

The second execution should make few or no unnecessary changes.

This validates an important infrastructure-as-code property:

> Running the same provisioning process repeatedly should keep the machines in the same desired state rather than continuously modifying them.

---

# 16. Local Ubuntu vs AWS Amazon Linux

An important distinction must be maintained throughout the rest of the project.

### Local development environment

The local Multipass machines use:

```text
Ubuntu 24.04 LTS
```

### AWS environment

The provided EC2 machines use:

```text
Amazon Linux 2023
ARM64
```

The local environment reproduces the **architecture and Kubernetes topology**, but it does not reproduce the exact operating system.

For example:

```text
Ubuntu 24.04
└── Debian family
    └── apt

Amazon Linux 2023
└── Fedora/RHEL-like ecosystem
    └── dnf
```

Consequently, future Ansible tasks or project components that depend on:

- package names;
- package managers;
- repository configuration;
- filesystem paths;
- system packages;
- architecture-specific binaries;

must not assume that an Ubuntu-specific implementation will work unchanged on the AWS machines.

Where necessary, Ansible tasks should detect the target operating system and execute the appropriate distribution-specific configuration.

---

# 17. Result of Phase 2

At the beginning of the phase:

```text
control-plane   → blank Ubuntu VM
worker-1        → blank Ubuntu VM
worker-2        → blank Ubuntu VM
```

After Ansible provisioning:

```text
                    Ansible
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
   control-plane    worker-1     worker-2
          │            │            │
       common        common       common
          │            │            │
     containerd    containerd    containerd
          │            │            │
       kubelet       kubelet      kubelet
       kubeadm       kubeadm      kubeadm
       kubectl       kubectl      kubectl
```

The three machines are therefore **Kubernetes-ready nodes**.

However:

```text
Kubernetes cluster
        ✗
```

The cluster has not yet been created.

The next phase will use the prepared infrastructure to initialize the control plane, join the worker nodes, and configure Kubernetes networking.

---

# Appendix — Local setup for team members

The Ansible configuration can be shared so every team member can reproduce the same three-node environment locally.

## Prerequisite

Install **Multipass** before starting.

The local machines created below run:

```text
Ubuntu 24.04 LTS
```

Remember that the final AWS environment runs **Amazon Linux 2023 ARM64**. Keep this difference in mind when implementing anything that depends directly on the operating system.

## 1. Create the VMs

Create:

```bash
multipass launch 24.04 --name control-plane --cpus 2 --memory 2G --disk 10G

multipass launch 24.04 --name worker-1 --cpus 2 --memory 2G --disk 10G

multipass launch 24.04 --name worker-2 --cpus 2 --memory 2G --disk 10G
```

Check them:

```bash
multipass list
```

Multipass assigns the private IP addresses automatically.

Therefore, **your IP addresses may be different from those used by another team member.**

## 2. Update the Ansible inventory

Copy the IP addresses shown by:

```bash
multipass list
```

into the shared inventory:

```ini
[kubernetes]
control-plane ansible_host=<CONTROL_PLANE_IP>
worker-1 ansible_host=<WORKER_1_IP>
worker-2 ansible_host=<WORKER_2_IP>

[kubernetes:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

The Ansible roles automatically use these addresses when configuring hostname resolution between the machines.

## 3. Check Ansible connectivity

From the Ansible directory:

```bash
ansible-inventory --graph
```

Then:

```bash
ansible all -m ping
```

All three machines should return successfully.

## 4. Prepare the nodes

Run:

```bash
ansible-playbook playbooks/prepare.yml
```

Ansible will automatically configure:

```text
Linux prerequisites
        ↓
kernel/network settings
        ↓
containerd
        ↓
kubeadm + kubelet + kubectl
```

## 5. Quick verification

Check containerd:

```bash
ansible all -a "systemctl is-active containerd"
```

Check Kubernetes:

```bash
ansible all -a "kubeadm version"
```

Check networking:

```bash
ansible all -a "sysctl net.ipv4.ip_forward"
```

Finally, verify that the workers can resolve the control plane:

```bash
ansible worker-1,worker-2 -a "ping -c 1 control-plane"
```

If these checks succeed, your three local machines are ready for the next Kubernetes provisioning phase.

**Do not manually run `kubeadm init` or `kubeadm join` yet** unless you are also following the next cluster-provisioning phase.
