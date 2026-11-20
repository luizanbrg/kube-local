# Phase 3 — Kubernetes Cluster Deployment with Ansible

## 1. Objective

The objective of Phase 3 is to deploy a functional Kubernetes cluster across three Ubuntu virtual machines using **Ansible and kubeadm**.

During the previous phases, we:

- **Phase 1:** Created three Ubuntu 24.04 virtual machines using Multipass and configured SSH connectivity and Ansible inventory.
- **Phase 2:** Prepared the machines for Kubernetes by installing containerd, kubeadm, kubelet, and kubectl, and configuring the operating system.

In Phase 3, we use Ansible to initialize the Kubernetes control plane and automatically join the two worker nodes.

The expected result is a Kubernetes cluster consisting of one control-plane node and two worker nodes.

At this stage, the nodes may report `NotReady` because the Container Network Interface (CNI) will be installed in Phase 4.

---

## 2. Infrastructure Overview

The local infrastructure consists of three Ubuntu 24.04 virtual machines running through Multipass on macOS.

| Hostname | IP address | Role |
|---|---|---|
| control-plane | 192.168.252.2 | Kubernetes control plane |
| worker-1 | 192.168.252.3 | Kubernetes worker |
| worker-2 | 192.168.252.4 | Kubernetes worker |

All machines communicate over the private Multipass network `192.168.252.0/24`.

The Mac acts as the Ansible controller and can also administer the Kubernetes cluster using kubectl.

### Kubernetes architecture

```text
                     macOS
              Ansible + kubectl
                       |
                       |
               192.168.252.0/24
                       |
        +--------------+--------------+
        |              |              |
        v              v              v
  control-plane     worker-1       worker-2
  192.168.252.2  192.168.252.3  192.168.252.4
        |              |              |
  kube-apiserver     kubelet        kubelet
  etcd              containerd     containerd
  scheduler
  controller-manager
  kubelet
  containerd
```

The control plane manages the cluster, while worker nodes execute application workloads.

---

## 3. Prerequisites

Before deploying Kubernetes, the following components must already be configured.

### Operating system

All three machines run Ubuntu 24.04 LTS.

### Container runtime

containerd must be installed and running on every machine.

Verify:

```bash
ansible kubernetes -b -m shell \
  -a 'systemctl is-active containerd'
```

Expected result:

```text
active
```

### Kubernetes packages

The following binaries must already be installed:

- kubeadm
- kubelet
- kubectl

Verify:

```bash
ansible kubernetes -b -m shell \
  -a 'kubeadm version -o short; kubelet --version'
```

### Swap

Swap must remain disabled according to our Phase 2 configuration.

Verify:

```bash
ansible kubernetes -b -m shell \
  -a 'swapon --show'
```

An empty result indicates that no swap devices are active.

### Ansible connectivity

Verify that Ansible can communicate with the three machines:

```bash
ansible all -m ping
```

Each host should return `SUCCESS` and `pong`.

### Resources and networking

The control-plane VM should have at least 2 CPUs and 2 GiB RAM. Additional memory is recommended.

The machines must have internet connectivity to download Kubernetes container images and must be able to communicate over the private network.

---

## 4. Ansible Project Structure

We extended the existing Ansible project from Phase 2.

```text
infra/
└── ansible/
    ├── ansible.cfg
    ├── inventory.ini
    ├── group_vars/
    │   └── all.yml
    ├── playbooks/
    │   ├── prepare.yml
    │   └── cluster.yml
    └── roles/
        ├── common/
        ├── containerd/
        ├── kubernetes/
        ├── control_plane/
        │   └── tasks/
        │       └── main.yml
        └── workers/
            └── tasks/
                └── main.yml
```

The first three roles belong to Phase 2.

Phase 3 introduces two additional roles:

| Role | Responsibility |
|---|---|
| control_plane | Initialize Kubernetes, configure kubectl, and generate a worker join command |
| workers | Join worker nodes to the existing Kubernetes cluster |

We also introduced `cluster.yml`, which orchestrates the deployment.

---

## 5. Ansible Inventory Configuration

The inventory separates control-plane and worker machines into different groups.

File: `ansible/inventory.ini`

```ini
[control_plane]
control-plane ansible_host=192.168.252.2

[workers]
worker-1 ansible_host=192.168.252.3
worker-2 ansible_host=192.168.252.4

[kubernetes:children]
control_plane
workers

[kubernetes:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

### Explanation

The `control_plane` group contains the machine responsible for cluster management.

The `workers` group contains the machines that will execute application workloads.

The `kubernetes` parent group includes all three machines, allowing us to execute commands across the entire cluster.

The inventory structure can be verified with:

```bash
ansible-inventory --graph
```

---

## 6. Kubernetes Shared Variables

To avoid hardcoding configuration values in multiple roles, we defined shared variables.

File: `ansible/group_vars/all.yml`

```yaml
---
k8s_control_plane_ip: "192.168.252.2"
k8s_api_port: 6443

k8s_pod_network_cidr: "10.244.0.0/16"
k8s_service_cidr: "10.96.0.0/12"

k8s_cri_socket: "unix:///run/containerd/containerd.sock"

k8s_admin_user: "ubuntu"
```

### Network configuration

Kubernetes uses different networks for nodes, Pods, and Services.

| Network | CIDR | Purpose |
|---|---|---|
| Multipass network | 192.168.252.0/24 | Communication between VMs |
| Pod network | 10.244.0.0/16 | Communication between Kubernetes Pods |
| Service network | 10.96.0.0/12 | Virtual IP addresses assigned to Kubernetes Services |

The Pod network will be configured by the CNI plugin during Phase 4.

The selected CIDR ranges must not overlap existing local or routed networks.

### Container runtime

The variable `k8s_cri_socket` specifies the containerd CRI socket used by kubeadm and kubelet.

---

## 7. Control-Plane Initialization

The control-plane role initializes the Kubernetes cluster using kubeadm.

File: `ansible/roles/control_plane/tasks/main.yml`

```yaml
---
- name: Initialize Kubernetes control plane
  ansible.builtin.command:
    argv:
      - kubeadm
      - init
      - "--apiserver-advertise-address={{ k8s_control_plane_ip }}"
      - "--pod-network-cidr={{ k8s_pod_network_cidr }}"
      - "--service-cidr={{ k8s_service_cidr }}"
      - "--cri-socket={{ k8s_cri_socket }}"
      - "--node-name={{ inventory_hostname }}"
  args:
    creates: /etc/kubernetes/admin.conf
  register: kubeadm_init

- name: Create kubectl configuration directory
  ansible.builtin.file:
    path: "/home/{{ k8s_admin_user }}/.kube"
    state: directory
    owner: "{{ k8s_admin_user }}"
    group: "{{ k8s_admin_user }}"
    mode: "0700"

- name: Copy Kubernetes admin configuration
  ansible.builtin.copy:
    src: /etc/kubernetes/admin.conf
    dest: "/home/{{ k8s_admin_user }}/.kube/config"
    remote_src: true
    owner: "{{ k8s_admin_user }}"
    group: "{{ k8s_admin_user }}"
    mode: "0600"

- name: Wait for Kubernetes API server
  ansible.builtin.wait_for:
    host: "{{ k8s_control_plane_ip }}"
    port: "{{ k8s_api_port }}"
    delay: 5
    timeout: 180

- name: Generate Kubernetes worker join command
  ansible.builtin.command:
    argv:
      - kubeadm
      - token
      - create
      - --print-join-command
  register: kubeadm_join_command
  changed_when: true
  no_log: true

- name: Store worker join command
  ansible.builtin.set_fact:
    k8s_join_command: "{{ kubeadm_join_command.stdout }}"
  no_log: true
```

### 7.1 Kubernetes initialization

The main operation is:

```bash
kubeadm init \
  --apiserver-advertise-address=192.168.252.2 \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --cri-socket=unix:///run/containerd/containerd.sock \
  --node-name=control-plane
```

This command initializes the control-plane components.

| Component | Function |
|---|---|
| kube-apiserver | Exposes the Kubernetes API |
| etcd | Stores Kubernetes cluster state |
| kube-scheduler | Assigns Pods to nodes |
| kube-controller-manager | Manages controllers and reconciles cluster state |
| kubelet | Manages Pods on the node |

Kubeadm creates the control-plane components as static Pods managed by kubelet.

### 7.2 Idempotency

The following configuration prevents Ansible from executing `kubeadm init` repeatedly:

```yaml
args:
  creates: /etc/kubernetes/admin.conf
```

If `/etc/kubernetes/admin.conf` already exists, Ansible skips initialization.

This protects against accidental reinitialization during subsequent playbook executions.

However, the presence of the file does not guarantee that initialization completed successfully. A partially initialized cluster requires additional diagnosis.

### 7.3 kubectl configuration

Kubeadm generates:

```text
/etc/kubernetes/admin.conf
```

This file contains the configuration and credentials needed to administer the cluster.

Ansible copies it to:

```text
/home/ubuntu/.kube/config
```

This allows the Ubuntu user to execute kubectl commands without sudo.

### 7.4 API server availability

The role waits for TCP port `6443` on the control-plane IP address.

Port `6443` is the default Kubernetes API server port.

This ensures that the API server endpoint is accepting connections before the playbook continues.

A TCP connectivity check does not replace an API readiness check.

### 7.5 Worker join command

The control-plane role generates a join command using:

```bash
kubeadm token create --print-join-command
```

The generated command has the following structure:

```bash
kubeadm join 192.168.252.2:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

The bootstrap token allows the worker to authenticate during the joining process.

The certificate authority hash allows the worker to verify the identity of the Kubernetes control plane.

The command is stored in an Ansible variable called `k8s_join_command`.

The tasks use `no_log: true` to prevent the bootstrap token from appearing in logs.

The token is generated dynamically and is not stored in the Git repository.

---

## 8. Worker Node Configuration

The workers role automatically joins both worker nodes to the Kubernetes cluster.

File: `ansible/roles/workers/tasks/main.yml`

```yaml
---
- name: Check whether worker already joined Kubernetes
  ansible.builtin.stat:
    path: /etc/kubernetes/kubelet.conf
  register: worker_kubelet_config

- name: Join worker to Kubernetes cluster
  ansible.builtin.command:
    cmd: >-
      {{ hostvars[groups['control_plane'][0]].k8s_join_command }}
      --cri-socket {{ k8s_cri_socket }}
      --node-name {{ inventory_hostname }}
  when: not worker_kubelet_config.stat.exists
  no_log: true
```

### 8.1 Checking cluster membership

Before executing the join command, Ansible checks for:

```text
/etc/kubernetes/kubelet.conf
```

This file is normally created when the worker successfully joins the cluster.

If the file exists, the join operation is skipped.

This avoids unnecessarily rejoining a previously initialized worker, although it is not a complete check of the node's current cluster membership.

### 8.2 Retrieving the join command

The following expression accesses the command generated on the control plane:

```yaml
hostvars[groups['control_plane'][0]].k8s_join_command
```

`hostvars` allows Ansible to access variables associated with another inventory host.

This allows the workers to retrieve the join command without manually copying tokens or certificates.

### 8.3 Joining the cluster

Ansible executes a command equivalent to:

```bash
kubeadm join 192.168.252.2:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --cri-socket unix:///run/containerd/containerd.sock \
  --node-name worker-1
```

The same operation is performed on `worker-2`, using its own node name.

Once the command succeeds, the worker registers with the Kubernetes API server.

---

## 9. Cluster Deployment Playbook

The deployment is orchestrated through a dedicated Ansible playbook.

File: `ansible/playbooks/cluster.yml`

```yaml
---
- name: Initialize Kubernetes control plane
  hosts: control_plane
  become: true
  gather_facts: true

  roles:
    - control_plane

- name: Join Kubernetes worker nodes
  hosts: workers
  become: true
  gather_facts: true

  roles:
    - workers
```

### Execution order

Ansible executes the plays sequentially.

**First play — Control plane**

1. Initialize Kubernetes.
2. Configure kubectl.
3. Wait for the API server.
4. Generate the worker join command.

**Second play — Workers**

1. Check whether each worker has already joined.
2. Retrieve the join command.
3. Join both workers to the Kubernetes cluster.

This ensures that the control plane is initialized before worker nodes attempt to join.

---

## 10. Ansible Configuration

The Ansible configuration defines the inventory and role paths.

File: `ansible/ansible.cfg`

```ini
[defaults]
inventory = ./inventory.ini
roles_path = ./roles
host_key_checking = True
```

Additional SSH settings from the previous phases should be preserved.

All deployment commands are executed from the root of the `ansible/` directory.

---

## 11. Deploying the Kubernetes Cluster

### Step 1 — Start the virtual machines

On macOS:

```bash
multipass start control-plane worker-1 worker-2
```

Verify:

```bash
multipass list
```

All three machines should be running.

### Step 2 — Verify Ansible connectivity

```bash
ansible all -m ping
```

All three machines should return `pong`.

### Step 3 — Validate the playbook

```bash
ansible-playbook playbooks/cluster.yml --syntax-check
```

Expected:

```text
playbook: playbooks/cluster.yml
```

### Step 4 — Verify container image access

List the required Kubernetes images:

```bash
ansible control_plane -b -m command \
  -a 'kubeadm config images list'
```

Test registry connectivity:

```bash
ansible control_plane -m shell \
  -a 'curl -IL --max-time 15 https://registry.k8s.io/v2/'
```

### Step 5 — Execute the deployment

```bash
ansible-playbook playbooks/cluster.yml
```

Ansible initializes the control plane and joins the workers automatically.

A successful execution should end with a recap showing zero failed and unreachable hosts.

---

## 12. Kubernetes Cluster Verification

### 12.1 Connect to the control plane

```bash
multipass shell control-plane
```

### 12.2 List Kubernetes nodes

```bash
kubectl get nodes
```

Expected before installing the CNI:

```text
NAME            STATUS     ROLES           AGE   VERSION
control-plane   NotReady   control-plane   2m    v1.x.x
worker-1        NotReady   <none>          1m    v1.x.x
worker-2        NotReady   <none>          1m    v1.x.x
```

The `NotReady` state is expected while Pod networking is not configured.

### 12.3 Verify cluster information

```bash
kubectl cluster-info
