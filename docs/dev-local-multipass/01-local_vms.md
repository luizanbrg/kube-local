# Phase 1 — Local VM Infrastructure

## Objective

The first phase consists of creating a local environment that reproduces the basic infrastructure of the final AWS environment.

Three Linux virtual machines are used:

| VM              | Role                          |
| --------------- | ----------------------------- |
| `control-plane` | Kubernetes control-plane node |
| `worker-1`      | Kubernetes worker node        |
| `worker-2`      | Kubernetes worker node        |

At this stage, Kubernetes and its dependencies are intentionally **not installed manually**. The machines serve as clean Linux hosts that will later be configured using Ansible.

The target architecture for this phase is:

```text
                     macOS Host
                         |
                      Ansible
                         |
                 SSH (local only)
                         |
            +------------+------------+
            |            |            |
            v            v            v
     control-plane    worker-1     worker-2
        Ubuntu          Ubuntu       Ubuntu
```

---

## 1. Virtualization with Multipass

Multipass is used to create lightweight Ubuntu virtual machines on macOS.

The three machines were created with Ubuntu 24.04 LTS:

```bash
multipass launch 24.04 \
  --name control-plane \
  --cpus 2 \
  --memory 4G \
  --disk 20G

multipass launch 24.04 \
  --name worker-1 \
  --cpus 2 \
  --memory 4G \
  --disk 20G

multipass launch 24.04 \
  --name worker-2 \
  --cpus 2 \
  --memory 4G \
  --disk 20G
```

Their state and IP addresses can be checked with:

```bash
multipass list
```

Example:

```text
Name             State      IPv4             Image
control-plane    Running    192.168.x.x      Ubuntu 24.04 LTS
worker-1         Running    192.168.x.x      Ubuntu 24.04 LTS
worker-2         Running    192.168.x.x      Ubuntu 24.04 LTS
```

The exact IP addresses depend on the Multipass network created on the Mac.

---

## 2. IP Address Strategy

The original infrastructure plan assumed that each VM would have a manually configured static IP address.

This was intentionally not done.

With the Multipass networking configuration used on macOS, the VMs obtain their addresses through DHCP. Trying to force static addresses inside the guests would introduce unnecessary network configuration and make the local environment more fragile.

Therefore:

```text
control-plane → DHCP address
worker-1      → DHCP address
worker-2      → DHCP address
```

Multipass remains the source used to determine the current addresses:

```bash
multipass list
```

or:

```bash
multipass info control-plane
multipass info worker-1
multipass info worker-2
```

The local Ansible inventory can consequently be updated if the DHCP addresses change.

This behavior is specific to the local development environment and does not define the networking strategy used later on AWS.

---

## 3. SSH Authentication

Ansible requires a connection mechanism for executing commands on the target machines.

For the local Multipass environment, SSH is used as the Ansible transport.

An SSH key pair on the Mac is used for authentication.

If necessary, a key can be generated with:

```bash
ssh-keygen -t ed25519
```

The public key is then added to each VM's `authorized_keys`.

For example:

```bash
cat ~/.ssh/id_ed25519.pub | \
multipass exec control-plane -- \
bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

The same operation is performed for `worker-1` and `worker-2`.

The default Ubuntu user provided by Multipass is:

```text
ubuntu
```

### SSH aliases

No aliases were added to:

```text
~/.ssh/config
```

Aliases such as:

```bash
ssh control-plane
ssh worker-1
ssh worker-2
```

are therefore not a requirement of this environment.

Instead, Ansible uses the current Multipass IP addresses directly through its inventory.

SSH is only being used as the **local Ansible transport**. It is not intended to reproduce how administrators connect to the final AWS instances.

---

## 4. Ansible Installation

Ansible runs from the macOS host and acts as the configuration-management tool for the three machines.

On macOS, it can be installed using Homebrew:

```bash
brew install ansible
```

The installation can be verified with:

```bash
ansible --version
```

The basic architecture is therefore:

```text
Ansible controller
       =
      Mac

Managed nodes
       =
control-plane
worker-1
worker-2
```

---

## 5. Ansible Inventory

An inventory file defines the machines managed by Ansible.

Example `inventory.ini`:

```ini
[kubernetes]
control-plane ansible_host=<CONTROL_PLANE_IP>
worker-1 ansible_host=<WORKER_1_IP>
worker-2 ansible_host=<WORKER_2_IP>

[kubernetes:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

For example, if Multipass reports:

```text
control-plane    192.168.252.2
worker-1         192.168.252.3
worker-2         192.168.252.4
```

the inventory becomes:

```ini
[kubernetes]
control-plane ansible_host=192.168.252.2
worker-1 ansible_host=192.168.252.3
worker-2 ansible_host=192.168.252.4

[kubernetes:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

The logical names used by Ansible are therefore independent from the actual IP addresses:

```text
control-plane ──→ 192.168.252.2
worker-1      ──→ 192.168.252.3
worker-2      ──→ 192.168.252.4
```

---

## 6. Ansible Configuration

An `ansible.cfg` file can define the local inventory as the default inventory:

```ini
[defaults]
inventory = inventory.ini
host_key_checking = False
interpreter_python = auto_silent
```

This avoids having to specify the inventory manually for every command.

Without this configuration, the inventory can instead be specified explicitly:

```bash
ansible all -i inventory.ini -m ping
```

---

## 7. Connectivity Verification

Before performing any Kubernetes installation, Ansible connectivity was tested.

First, the hosts recognized by the inventory can be displayed with:

```bash
ansible all --list-hosts
```

Expected result:

```text
hosts (3):
  control-plane
  worker-1
  worker-2
```

The Ansible connectivity test is then executed:

```bash
ansible all -m ping
```

A successful result looks like:

```text
control-plane | SUCCESS => {
    "changed": false,
    "ping": "pong"
}

worker-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}

worker-2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

The Ansible `ping` module is different from the normal ICMP `ping` command.

It verifies that Ansible can:

```text
connect to the host
        ↓
authenticate through SSH
        ↓
execute Python remotely
        ↓
receive a response
```

Therefore, receiving `pong` from all three machines confirms that the nodes are ready to be managed by Ansible.

---

## 8. Difference Between Local and AWS Access

SSH is used here because it provides a simple transport between the Mac and the local Multipass virtual machines.

It should not be confused with the access mechanism of the final AWS environment.

The AWS instances are accessed through AWS Systems Manager Session Manager (SSM), for example:

```bash
aws --profile kubequest2 ssm start-session \
  --target <INSTANCE_ID>
```

The AWS environment does not require exposing SSH port `22` to the Internet.

Therefore, the environments currently differ at the connection layer:

```text
LOCAL

Mac
 |
 | Ansible over SSH
 |
 +-- control-plane
 +-- worker-1
 +-- worker-2
```

```text
AWS

Mac
 |
 | AWS Systems Manager
 |
 +-- EC2 instances

No public SSH access required
```

The purpose of the local environment is primarily to develop and validate the **Ansible provisioning logic**.

The Ansible roles and playbooks created in later phases should contain the actual system configuration so that the same infrastructure logic can subsequently be adapted to the AWS environment without manually reproducing every installation step.

---

## Milestone 1 — Completed

At the end of Phase 1:

- Three Ubuntu 24.04 virtual machines exist.
- The machines are named `control-plane`, `worker-1`, and `worker-2`.
- Multipass manages their local networking.
- Their addresses are obtained through DHCP rather than forced static IP configuration.
- SSH authentication is available for Ansible locally.
- No SSH aliases are required in `~/.ssh/config`.
- Ansible recognizes all three nodes.
- Ansible can successfully execute commands on all three machines.
- Kubernetes has not yet been installed manually.

The resulting infrastructure is:

```text
                         Mac
                          |
                       Ansible
                          |
                     local SSH
                          |
             +------------+------------+
             |            |            |
             v            v            v
      control-plane    worker-1     worker-2
      Ubuntu 24.04    Ubuntu 24.04 Ubuntu 24.04
             |            |            |
             +------------+------------+
                          |
                 Ready for Phase 2
```

The validation command for this milestone is:

```bash
ansible all -m ping
```

with all three nodes returning:

```text
SUCCESS
ping: pong
```

This establishes the clean infrastructure baseline from which the Kubernetes cluster can be provisioned using Ansible.
