# PHASE 4 — Kubernetes Cluster Networking with Calico

**Project:** Kubernetes / AWS — Epitech KUBE
**Environment:** macOS + Multipass + Ubuntu 24.04 LTS
**Provisioning:** Ansible
**Kubernetes version:** v1.35.9
**CNI:** Calico v3.33.0
**Status:** Completed — cluster networking operational and Phase 4 playbook idempotent

---

# 1. Objective

The objective of Phase 4 was to install and configure the Kubernetes networking layer using **Calico**, after creating the Kubernetes cluster during Phase 3.

At the end of Phase 3, all three nodes had joined the cluster, but Kubernetes networking was not yet fully functional.

In particular:

- Kubernetes nodes were initially `NotReady`.
- CoreDNS Pods could not start normally.
- Pod-to-Pod communication across different nodes was not available.
- Kubernetes NetworkPolicies could not be enforced without a suitable networking implementation.

Phase 4 addresses these limitations by installing a Container Network Interface (CNI) implementation.

Our goals were to:

1. Deploy Calico using Ansible.
2. Configure the Pod network with our existing `10.244.0.0/16` CIDR.
3. Enable communication between Pods running on different nodes.
4. Verify Kubernetes Service connectivity and DNS resolution.
5. Validate Kubernetes NetworkPolicy enforcement.
6. Verify that all three nodes become `Ready`.
7. Make the Ansible configuration idempotent.

We deliberately did not deploy additional platform components such as Argo CD, Grafana, Prometheus, or ingress controllers during this phase.

---

# 2. Existing infrastructure

We reused the environment created during Phases 1–3.

## 2.1 Virtual machines

Our three Ubuntu VMs run on macOS using Multipass.

| VM            | IP address    | Kubernetes role |
| ------------- | ------------- | --------------- |
| control-plane | 192.168.252.2 | Control plane   |
| worker-1      | 192.168.252.3 | Worker          |
| worker-2      | 192.168.252.4 | Worker          |

All three machines run Ubuntu 24.04 LTS with containerd as their container runtime.

Ansible executes from the Mac and connects to the VMs through SSH.

Kubernetes was installed and initialized in the previous phases using `kubeadm`.

## 2.2 Kubernetes network configuration

We established the following network ranges during Phase 3:

| Network         | CIDR             | Purpose                                              |
| --------------- | ---------------- | ---------------------------------------------------- |
| VM network      | 192.168.252.0/24 | Communication between Multipass VMs                  |
| Pod network     | 10.244.0.0/16    | IP addresses assigned to Kubernetes Pods             |
| Service network | 10.96.0.0/12     | Virtual IP addresses assigned to Kubernetes Services |

Calico must use the same Pod CIDR configured during `kubeadm init`.

## 2.3 Existing Ansible configuration

Before Phase 4, our Ansible roles were responsible for:

- Preparing the Ubuntu operating systems.
- Configuring kernel modules and sysctl parameters.
- Installing and configuring containerd.
- Installing Kubernetes packages.
- Initializing the control plane.
- Generating and executing worker join commands.

Phase 4 adds a dedicated `calico` role without replacing the previous phases.

---

# 3. Understanding Calico

## 3.1 What is a CNI?

CNI stands for **Container Network Interface**.

Kubernetes is responsible for orchestrating containers, but it relies on a networking implementation to provide connectivity between Pods.

A CNI implementation configures Pod network interfaces, assigns or manages networking addresses, and enables communication between Pods.

Without a functional CNI, a kubeadm-based Kubernetes cluster will generally not become fully operational.

## 3.2 Why Calico?

We selected Calico because it supports:

- Pod IP address management.
- Pod-to-Pod communication.
- Communication between Pods hosted on different nodes.
- Kubernetes NetworkPolicy enforcement.
- Multiple networking approaches, including VXLAN and BGP.
- Operator-based installation and lifecycle management.

NetworkPolicy support is particularly important because our project includes additional security requirements.

## 3.3 Networking mode

We configured Calico using:

| Parameter         | Value           |
| ----------------- | --------------- |
| CNI               | Calico          |
| Version           | v3.33.0         |
| Deployment method | Tigera Operator |
| Encapsulation     | VXLAN           |
| BGP               | Disabled        |
| Pod CIDR          | 10.244.0.0/16   |
| Outgoing NAT      | Enabled         |
| IP block size     | /26             |

### VXLAN

VXLAN encapsulates Pod traffic inside packets transported across the underlying node network.

For example:

```text
worker-1 (192.168.252.3)
    |
    | Pod A (10.244.x.x)
    |
    | VXLAN encapsulation
    |
    v
VM network (192.168.252.0/24)
    |
    v
worker-2 (192.168.252.4)
    |
    | VXLAN decapsulation
    |
    v
Pod B (10.244.y.y)
```

Calico uses the underlying network to transport encapsulated Pod packets.

This allows Pods on different machines to communicate without requiring physical or virtual network infrastructure to have a route to every Pod subnet.

For VXLAN, the underlying network must permit UDP port `4789` between the nodes.

We disabled BGP because we selected VXLAN-based overlay networking for our local environment.

---

# 4. Ansible project structure

We created a dedicated role for networking.

Our relevant project structure became:

```text
ansible/
├── inventory.ini
├── ansible.cfg
│
├── files/
│   └── calico/
│       ├── v3_projectcalico_org-v1beta1.yaml
│       ├── tigera-operator.yaml
│       └── tigera-operator-normalized.yaml
│
├── roles/
│   ├── common/
│   ├── containerd/
│   ├── kubernetes/
│   ├── control_plane/
│   ├── workers/
│   │
│   └── calico/
│       ├── defaults/
│       │   └── main.yml
│       ├── tasks/
│       │   └── main.yml
│       └── templates/
│           └── custom-resources.yaml.j2
│
└── phase4-networking.yml
```

The directory `files/calico/` contains the version-pinned Kubernetes manifests.

The Ansible role handles their deployment.

The Jinja2 template defines our desired Calico configuration.

We also retained a normalized version of the Tigera Operator manifest to address an idempotency issue discovered during testing.

## 4.1 Creating the directories

From the Ansible directory:

```bash
mkdir -p roles/calico/{defaults,tasks,templates}
mkdir -p files/calico
```

Create the role files:

```bash
touch roles/calico/defaults/main.yml
touch roles/calico/tasks/main.yml
touch roles/calico/templates/custom-resources.yaml.j2
touch phase4-networking.yml
```

---

# 5. Downloading the Calico manifests

We selected the Tigera Operator installation method.

The operator is responsible for deploying and managing Calico components across Kubernetes.

We downloaded two version-pinned upstream manifests.

## 5.1 Calico CRDs

```bash
curl -fL \
  https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/v3_projectcalico_org-v1beta1.yaml \
  -o files/calico/v3_projectcalico_org-v1beta1.yaml
```

CRD means **CustomResourceDefinition**.

CRDs extend the Kubernetes API by introducing additional resource types.

Calico uses custom resources to represent its configuration, including IP pools, network policies, and operator settings.

## 5.2 Tigera Operator

```bash
curl -fL \
  https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml \
  -o files/calico/tigera-operator.yaml
```

The operator continuously reconciles Calico components with the desired configuration.

## 5.3 Why store the manifests locally?

We deliberately stored the manifests in Git instead of downloading them during every Ansible execution.

Advantages:

- The Calico version is explicitly pinned.
- Deployments are more reproducible.
- Upstream manifest changes cannot silently affect an existing deployment.
- The same manifests can be used locally and later in AWS.
- Ansible doesn't depend on downloading manifests at execution time.

However, the Kubernetes nodes still need access to the required container images, unless those images are already cached or provided through an accessible registry.

---

# 6. Configuring the Calico Ansible role

## 6.1 Role variables

File:

```text
roles/calico/defaults/main.yml
```

Configuration:

```yaml
---
calico_version: 'v3.33.0'

calico_pod_cidr: '10.244.0.0/16'

calico_encapsulation: 'VXLAN'
calico_bgp: 'Disabled'

calico_kubeconfig: '/etc/kubernetes/admin.conf'

calico_remote_dir: '/tmp/calico'

calico_manifest_dir: '{{ playbook_dir }}/files/calico'
```

These variables describe how Calico should be deployed.

`calico_pod_cidr` must match the Pod CIDR configured in Phase 3.

`calico_kubeconfig` points to the admin kubeconfig created by `kubeadm init`.

`calico_remote_dir` is the temporary directory on the control-plane VM where Ansible copies the manifests.

## 6.2 Jinja2 configuration template

File:

```text
roles/calico/templates/custom-resources.yaml.j2
```

Our final template:

```yaml
---
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  variant: Calico

  calicoNetwork:
    bgp: {{calico_bgp}}

    ipPools:
      - name: default-ipv4-ippool
        cidr: '{{ calico_pod_cidr }}'
        encapsulation: {{calico_encapsulation}}
        natOutgoing: Enabled
        nodeSelector: all()

        allowedUses:
          - Workload
          - Tunnel
        assignmentMode: Automatic
        blockSize: 26
        disableBGPExport: false
        disableNewAllocations: false

---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
```

### Installation resource

The `Installation` resource instructs the operator to deploy Calico with our selected networking configuration.

### IP pool

The default IPv4 pool uses:

```yaml
cidr: '10.244.0.0/16'
```

This is the address range Calico uses for Pod networking.

### IP allocation

```yaml
allowedUses:
  - Workload
  - Tunnel
assignmentMode: Automatic
blockSize: 26
```

These parameters configure automatic IP allocation for workloads and tunnel endpoints.

The `/26` block size is an IPAM allocation setting; it does not mean that the cluster's overall Pod CIDR is `/26`.

### APIServer

The `APIServer` resource enables Calico's additional API functionality.

---

# 7. Deploying Calico through Ansible

File:

```text
roles/calico/tasks/main.yml
```

The role performs the following operations in order.

## 7.1 Prepare the control-plane VM

First, Ansible creates:

```text
/tmp/calico/
```

It then copies the manifests to that directory:

```text
/tmp/calico/
├── calico-crds.yaml
├── tigera-operator.yaml
└── custom-resources.yaml
```

The custom resources file is generated using Jinja2.

## 7.2 Install Calico CRDs

Ansible executes the equivalent of:

```bash
kubectl apply \
  --server-side \
  --force-conflicts \
  -f /tmp/calico/calico-crds.yaml
```

We used server-side apply for the large Calico CRD manifest.

The `--force-conflicts` option permits the applying field manager to take ownership of conflicting fields. It should be used deliberately, particularly when upgrading an existing installation.

## 7.3 Install the Tigera Operator

Next:

```bash
kubectl apply -f /tmp/calico/tigera-operator.yaml
```

The operator is installed in:

```text
tigera-operator
```

Ansible waits for the operator Deployment to become available:

```bash
kubectl rollout status \
  deployment/tigera-operator \
  -n tigera-operator \
  --timeout=300s
```

## 7.4 Apply Calico custom resources

Once the operator is available:

```bash
kubectl apply -f /tmp/calico/custom-resources.yaml
```

This creates the operator's desired `Installation` and `APIServer` resources.

## 7.5 Wait for Calico readiness

Our role includes a wait for the Calico TigeraStatus resource to exist before waiting for the installation to become available.

This was an improvement made during troubleshooting to avoid checking Calico readiness before the operator had created its status resource.

The role then waits for all Kubernetes nodes to become `Ready`.

Conceptually, the installation process is:

```text
Ansible
   |
   v
Copy version-pinned manifests
   |
   v
Install Calico CRDs
   |
   v
Deploy Tigera Operator
   |
   v
Wait for operator availability
   |
   v
Create Installation + APIServer resources
   |
   v
Tigera Operator deploys Calico
   |
   v
Calico initializes networking on the nodes
   |
   v
Kubernetes nodes become Ready
```

## 7.6 Important implementation detail

Ansible installs Calico by executing Kubernetes API operations on the control-plane VM.

It does not manually install Calico binaries on each worker using SSH.

The Tigera Operator deploys the required Kubernetes components, including the Calico node agents.

This separation is useful because the Ansible role remains simple and the operator is responsible for managing Calico's runtime components.

---

# 8. Phase 4 playbook

We created:

```text
phase4-networking.yml
```

Content:

```yaml
---
- name: Phase 4 - Install Kubernetes networking with Calico
  hosts: control_plane
  become: true
  gather_facts: true

  roles:
    - calico
```

## 8.1 Naming clarification

Our actual VM is named:

```text
control-plane
```

However, the Ansible inventory group is named:

```text
control_plane
```

These are not the same identifier.

The playbook targets the inventory group, while the actual execution takes place on the VM named `control-plane`.

We confirmed this during troubleshooting when Ansible reported:

```text
ok: [control-plane]
```

Therefore, there was no naming problem, and no renaming was necessary.

## 8.2 Executing the playbook

From the Ansible directory on the Mac:

```bash
ansible-playbook -i inventory.ini \
  phase4-networking.yml
```

This runs the entire Calico installation on the existing Kubernetes cluster.

---

# 9. Issue 1 — Unsupported MutatingAdmissionPolicy resources

During the first Calico installation attempt, Ansible failed while applying the CRDs.

The error included:

```text
no matches for kind "MutatingAdmissionPolicy"
in version "admissionregistration.k8s.io/v1beta1"
```

And:

```text
no matches for kind "MutatingAdmissionPolicyBinding"
```

## 9.1 Cause

The Calico v3.33.0 manifest contained admission policy resources that our Kubernetes API server did not recognize.

Our Kubernetes version was v1.35.x.

In Kubernetes 1.35, the relevant MutatingAdmissionPolicy functionality was a beta feature that required explicit activation.

The failure was therefore related to Kubernetes API compatibility, not to the control-plane VM name or Ansible inventory.

## 9.2 Resolution

We enabled the relevant Kubernetes API server feature and API version.

The API server static Pod manifest is located at:

```text
/etc/kubernetes/manifests/kube-apiserver.yaml
```

The required flags were:

```yaml
- --feature-gates=MutatingAdmissionPolicy=true
- --runtime-config=admissionregistration.k8s.io/v1beta1=true
```

These flags were added to the existing API server command configuration, without removing the other parameters.

Because the API server runs as a static Pod, kubelet detects modifications to its manifest and restarts it.

We then reran Phase 4.

## 9.3 Important reproducibility requirement

This correction must also be represented in our **Phase 3 Ansible/kubeadm configuration**.

A manual change made directly to the VM is not sufficient for reproducibility.

If the cluster is recreated from scratch without these flags, the original Calico installation problem may return.

**Status:** The running cluster was corrected. Persistence of this change in the Phase 3 bootstrap configuration still needs to be verified before the full rebuild test.

---

# 10. Issue 2 — ImagePullBackOff during networking tests

After installing Calico, we created two test Pods using the NGINX image:

```yaml
image: nginx:1.27
```

However, both Pods initially failed to start.

Example:

```text
NAME             READY   STATUS             NODE
test-worker-1    0/1     ImagePullBackOff   worker-1
test-worker-2    0/1     ImagePullBackOff   worker-2
```

Despite the image-pull failure, both Pods had received addresses from the Calico Pod network:

```text
test-worker-1   10.244.226.66
test-worker-2   10.244.133.199
```

This was evidence that Pod network setup was progressing, but it did not yet prove successful cross-node connectivity.

## 10.1 Diagnosing the failure

We inspected the Kubernetes Pod events:

```bash
kubectl describe pod test-worker-1 \
  -n networking-test
```

The events revealed a TLS validation error when contacting Docker Hub:

```text
tls: failed to verify certificate:
x509: certificate has expired or is not yet valid
```

The important detail was:

```text
current time 2026-10-26
is before 2026-11-03
```

This indicated that the VM's clock was earlier than the certificate's validity start date.

The image itself was not the underlying problem.

## 10.2 Verifying the clock

On `worker-1`:

```bash
timedatectl status
```

We discovered:

```text
Local time: Mon 2026-10-26
RTC time: Fri 2026-11-06

System clock synchronized: no
NTP service: active
```

The VM's system clock was approximately 11 days behind.

The incorrect system time caused TLS certificate validation to fail.

## 10.3 Fixing the clocks

We synchronized the VMs with the Mac's current time.

From macOS:

```bash
for vm in control-plane worker-1 worker-2; do
  echo "===== $vm ====="
  multipass exec "$vm" -- sudo date -s "@$(date +%s)"
done
```

This uses the Mac's current Unix timestamp to set the system clock on each VM.

After correcting the clock, Kubernetes was able to download the NGINX images, and the test Pods reached `Running`.

## 10.4 Why crictl was not used

We initially attempted:

```bash
sudo crictl pull docker.io/library/nginx:1.27
```

But received:

```text
sudo: crictl: command not found
```

The `crictl` utility was not installed on the VM.

This did not prevent Kubernetes from using containerd.

It was unnecessary to install `crictl` to resolve the issue, since the actual cause was the incorrect system time.

---

# 11. Issue 3 — Chrony installed but not synchronized

We investigated time synchronization to prevent the TLS problem from recurring.

Initially, the following command failed:

```bash
sudo systemctl restart systemd-timesyncd
```

Because:

```text
Unit systemd-timesyncd.service not found.
```

We then identified the actual time synchronization service.

```bash
systemctl list-unit-files | grep -Ei 'chrony|timesync|ntp'
```

The VM was using **Chrony**.

## 11.1 Initial Chrony status

We inspected:

```bash
chronyc tracking
```

Initially, the result included:

```text
Reference ID : 00000000
Stratum      : 0
Leap status  : Not synchronised
```

This indicated that Chrony had not established a valid synchronization source.

## 11.2 Investigating NTP sources

We ran:

```bash
chronyc sources -v
```

And:

```bash
chronyc activity
```

After the clocks were corrected and Chrony obtained NTP measurements, it selected a synchronization source.

In Chrony's source output:

```text
^*
```

indicates the currently selected NTP server.

We also inspected:

```text
/etc/chrony/chrony.conf
```

The configuration already contained Ubuntu NTP pools:

```text
pool ntp.ubuntu.com iburst maxsources 4
pool 0.ubuntu.pool.ntp.org iburst maxsources 1
pool 1.ubuntu.pool.ntp.org iburst maxsources 1
pool 2.ubuntu.pool.ntp.org iburst maxsources 2
```

Therefore, it was unnecessary to replace the NTP configuration or install another time synchronization service.

## 11.3 Final synchronization verification

We verified all three VMs:

```bash
for vm in control-plane worker-1 worker-2; do
  echo "===== $vm ====="
  multipass exec "$vm" -- chronyc tracking | \
    grep -E 'Stratum|System time|Leap status'
done
```

Final results:

| VM            | Stratum | Offset       | Leap status |
| ------------- | ------- | ------------ | ----------- |
| control-plane | 3       | 0.60 ms slow | Normal      |
| worker-1      | 3       | 0.93 ms fast | Normal      |
| worker-2      | 3       | 0.13 ms slow | Normal      |

All three VMs had valid synchronization sources and very small reported clock offsets.

## 11.4 Improving the existing Ansible common role

We updated the Phase 2 `common` role to verify time synchronization.

File:

```text
roles/common/tasks/main.yml
```

The additional tasks were:

```yaml
- name: Wait for Chrony time synchronization
  ansible.builtin.command:
    cmd: chronyc waitsync 12 1 0 10
  register: chrony_sync
  changed_when: false
  retries: 2
  delay: 10
  until: chrony_sync.rc == 0

- name: Display Chrony synchronization status
  ansible.builtin.command:
    cmd: chronyc tracking
  register: chrony_tracking
  changed_when: false

- name: Show Chrony tracking information
  ansible.builtin.debug:
    var: chrony_tracking.stdout_lines
```

These tasks verify that Chrony is synchronized rather than merely running.

This is an important distinction: a service can be active without successfully synchronizing the clock.

The role now has a verification mechanism, although the full provisioning workflow should still be tested after VM recreation.

---

# 12. Validating cross-node Pod communication

Once Calico was operational and the time synchronization issue was resolved, we tested Pod networking.

## 12.1 Create a test namespace

```bash
kubectl create namespace networking-test
```

## 12.2 Create the test Pods

File:

```text
networking-test.yaml
```

Configuration:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-worker-1
  namespace: networking-test
spec:
  nodeName: worker-1
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80

---
apiVersion: v1
kind: Pod
metadata:
  name: test-worker-2
  namespace: networking-test
spec:
  nodeName: worker-2
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
```

We explicitly assigned each Pod to a worker node using `nodeName`.

This was done for testing purposes to guarantee that the Pods were hosted on different VMs.

Normally, Kubernetes schedules Pods automatically.

## 12.3 Deploy the test Pods

```bash
kubectl apply -f networking-test.yaml
```

Check:

```bash
kubectl get pods -n networking-test -o wide
```

After fixing the time synchronization problem, both NGINX Pods started successfully.

## 12.4 Test Pod-to-Pod communication

Retrieve the IP of the Pod running on `worker-2`:

```bash
POD_IP=$(kubectl get pod test-worker-2 \
  -n networking-test \
  -o jsonpath='{.status.podIP}')
```

Then execute an HTTP request from the Pod running on `worker-1`:

```bash
kubectl exec -n networking-test test-worker-1 \
  -- curl -fsS "http://$POD_IP"
```

The request returned the NGINX HTML response.

**Result: cross-node Pod-to-Pod communication was successfully validated.**

This confirmed that Pods running on different Kubernetes workers could communicate using their Pod IP addresses.

No host port publishing was required.

---

# 13. Testing Kubernetes Services and DNS

After validating direct Pod communication, we proceeded to Kubernetes Services.

## 13.1 Why use Services?

Pod IP addresses are not intended to provide stable application endpoints.

When a Pod is recreated, its IP may change.

A Kubernetes Service provides a stable virtual IP and DNS name through which applications can communicate.

## 13.2 Create a Service

We created a Service targeting the NGINX Pod on `worker-2`.

```bash
kubectl expose pod test-worker-2 \
  -n networking-test \
  --name=nginx-test \
  --port=80 \
  --target-port=80
```

The Service uses the `ClusterIP` type.

We verified its configuration and backend selection using:

```bash
kubectl get services -n networking-test
```

And:

```bash
kubectl get endpointslices \
  -n networking-test \
  -l kubernetes.io/service-name=nginx-test \
  -o wide
```

For reproducible future tests, the Pod should have an explicit label such as `app=nginx-server`, and the Service selector must match that label.

## 13.3 Test internal DNS

We used the full Kubernetes Service DNS name:

```text
nginx-test.networking-test.svc.cluster.local
```

From `test-worker-1`:

```bash
kubectl exec -n networking-test test-worker-1 \
  -- getent hosts \
  nginx-test.networking-test.svc.cluster.local
```

The expected result is the Service's ClusterIP.

## 13.4 Test Service connectivity

We then tested HTTP connectivity:

```bash
kubectl exec -n networking-test test-worker-1 \
  -- curl -fsS \
  http://nginx-test.networking-test.svc.cluster.local
```

The purpose was to verify that:

- CoreDNS resolves Kubernetes Service names.
- The Service directs traffic to its backend.
- The backend is reachable even when the client runs on a different node.

These tests establish the functionality needed for service-to-service communication in future applications.

---

# 14. Testing Kubernetes NetworkPolicy

Calico supports Kubernetes NetworkPolicies, allowing us to control which Pods can communicate.

We performed a basic deny-ingress test using our two NGINX Pods.

## 14.1 Label the test Pods

```bash
kubectl label pod test-worker-1 \
  -n networking-test \
  app=nginx-client --overwrite
```

```bash
kubectl label pod test-worker-2 \
  -n networking-test \
  app=nginx-server --overwrite
```

Labels allow NetworkPolicies to select specific Pods.

## 14.2 Create a deny-ingress policy

File:

```text
deny-ingress.yaml
```

Configuration:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-nginx-ingress
  namespace: networking-test
spec:
  podSelector:
    matchLabels:
      app: nginx-server

  policyTypes:
    - Ingress

  ingress: []
```

This policy selects the Pod labeled:

```text
app=nginx-server
```

And denies incoming traffic to that Pod, unless another applicable policy explicitly allows it.

## 14.3 Apply the policy

```bash
kubectl apply -f deny-ingress.yaml
```

Then test connectivity again:

```bash
kubectl exec -n networking-test test-worker-1 \
  -- curl --connect-timeout 3 --max-time 5 \
  "http://$POD_IP"
```

The expected behavior is a connection timeout.

## 14.4 Remove the policy

```bash
kubectl delete -f deny-ingress.yaml
```

Then retry the HTTP request:

```bash
kubectl exec -n networking-test test-worker-1 \
  -- curl -fsS "http://$POD_IP"
```

The connection should work again.

This procedure demonstrates how NetworkPolicies can restrict and restore network communication.

It also provides a basic validation method that can be reused when we implement the project's security requirements.

---

# 15. Verifying Kubernetes cluster health

After installing Calico, we checked the Kubernetes cluster.

## 15.1 Node readiness

```bash
kubectl get nodes -o wide
```

Our final Ansible output showed:

```text
NAME            STATUS   ROLES           VERSION
control-plane   Ready    control-plane   v1.35.9
worker-1        Ready    <none>          v1.35.9
worker-2        Ready    <none>          v1.35.9
```

All three nodes were healthy.

## 15.2 Verify Calico

```bash
kubectl get pods -n calico-system -o wide
```

```bash
kubectl get pods -n tigera-operator
```

```bash
kubectl get tigerastatus
```

The Ansible role successfully completed the checks for Calico installation availability and node readiness.

## 15.3 Verify CoreDNS

```bash
kubectl get pods -n kube-system
```

```bash
kubectl rollout status deployment/coredns \
  -n kube-system --timeout=180s
```

CoreDNS is particularly important because it provides DNS-based service discovery inside Kubernetes.

## 15.4 Clean up temporary resources

After the networking tests:

```bash
kubectl delete namespace networking-test
```

This removes the temporary NGINX Pods, Service, and NetworkPolicy resources.

The Calico installation is not affected.

The test manifests may be retained in Git for future validation after cluster rebuilds.

---

# 16. Issue 4 — Ansible idempotency

After successfully deploying Calico, we tested whether the Phase 4 playbook was idempotent.

Idempotency means that running the same automation repeatedly against an already correctly configured system should not introduce unnecessary changes.

Initially, our playbook completed successfully but reported:

```text
changed=2
```

Even on repeated executions.

The affected tasks were:

```text
Install Tigera Operator
Install Calico custom resources
```

We investigated both separately.

---

# 17. Fixing repeated changes to Calico custom resources

The first repeated change concerned:

```text
installation.operator.tigera.io/default
```

We executed:

```bash
kubectl diff -f /tmp/calico/custom-resources.yaml
```

The output showed that the live Calico Installation contained default IP pool values missing from our Jinja2 template.

These included:

```yaml
allowedUses:
  - Workload
  - Tunnel

assignmentMode: Automatic
blockSize: 26
disableBGPExport: false
disableNewAllocations: false
```

Kubernetes was repeatedly reconciling those fields when the Installation resource was applied.

## 17.1 Resolution

We updated:

```text
roles/calico/templates/custom-resources.yaml.j2
```

To explicitly include the relevant default values.

We preserved the existing pool block size of `26`.

Changing the block size of an active Calico IP pool is not necessary for idempotency and can require a more involved migration procedure.

After updating the template and rerunning Ansible, the Calico custom resources task became idempotent:

```text
TASK [calico : Install Calico custom resources]
ok: [control-plane]
```

However, the Tigera Operator task continued reporting a change.

The overall result became:

```text
changed=1
```

---

# 18. Fixing repeated changes to the Tigera Operator

The remaining issue concerned:

```text
TASK [calico : Install Tigera Operator]
changed: [control-plane]
```

We manually executed the corresponding apply command:

```bash
multipass exec control-plane -- \
  sudo env KUBECONFIG=/etc/kubernetes/admin.conf \
  kubectl apply -f /tmp/calico/tigera-operator.yaml
```

The output included:

```text
serviceaccount/tigera-operator configured
deployment.apps/tigera-operator configured
```

However, `kubectl diff` showed no substantive difference.

## 18.1 Inspect resource configurations

We inspected the last-applied configurations:

```bash
kubectl apply view-last-applied \
  serviceaccount/tigera-operator \
  -n tigera-operator
```

```bash
kubectl apply view-last-applied \
  deployment/tigera-operator \
  -n tigera-operator
```

We also inspected managed fields:

```bash
kubectl get serviceaccount tigera-operator \
  -n tigera-operator \
  -o yaml --show-managed-fields
```

```bash
kubectl get deployment tigera-operator \
  -n tigera-operator \
  -o yaml --show-managed-fields
```

The Deployment remained healthy, with one available replica and generation `1`.

## 18.2 Compare resource versions

We inspected the resource versions before and after applying the operator manifest.

Example:

```text
ServiceAccount resourceVersion: 334621
Deployment resourceVersion:     337764
```

The values did not change after the apply operation, despite the command reporting `configured`.

This suggested that no persistent resource update was taking place.

## 18.3 Identify the problematic fields

We inspected the original upstream manifest:

```bash
grep -n -A 5 -B 3 \
  -E 'imagePullSecrets:|name: WATCH_NAMESPACE' \
  files/calico/tigera-operator.yaml
```

We identified two empty values.

In the ServiceAccount:

```yaml
imagePullSecrets: []
```

In the Deployment:

```yaml
- name: WATCH_NAMESPACE
  value: ''
```

Kubernetes omitted these empty values in the stored live resource representation.

The interaction between these fields and client-side `kubectl apply` was the likely cause of the repeated `configured` output.

## 18.4 Create a normalized manifest

Rather than modifying the original upstream manifest, we created a copy:

```bash
cp files/calico/tigera-operator.yaml \
   files/calico/tigera-operator-normalized.yaml
```

In the normalized version, we removed:

```yaml
imagePullSecrets: []
```

And changed:

```yaml
- name: WATCH_NAMESPACE
  value: ''
```

To:

```yaml
- name: WATCH_NAMESPACE
```

No other operator settings were intentionally changed.

This preserved the original version-pinned upstream manifest for reference.

## 18.5 Update the Ansible copy task

In:

```text
roles/calico/tasks/main.yml
```

We modified the task responsible for copying the operator manifest.

The final version:

```yaml
- name: Copy Tigera Operator manifest
  ansible.builtin.copy:
    src: '{{ calico_manifest_dir }}/tigera-operator-normalized.yaml'
    dest: '{{ calico_remote_dir }}/tigera-operator.yaml'
    mode: '0644'
```

The destination filename remained the same.

Therefore, the remaining role tasks did not need to change.

## 18.6 Final idempotency test

We executed:

```bash
ansible-playbook -i inventory.ini \
  phase4-networking.yml
```

And repeated the execution without changing the configuration.

**Final result:**

```text
PLAY RECAP
control-plane : ok=14 changed=0 unreachable=0 failed=0
```

This confirmed that our Phase 4 playbook could be executed repeatedly without reporting unnecessary changes.

We did not suppress changes artificially with:

```yaml
changed_when: false
```

on the installation tasks.

Instead, we corrected the manifest configurations responsible for repeated apply operations.

---

# 19. Final architecture

Our local Kubernetes cluster now has the following architecture:

```text
                       macOS
               Ansible + kubectl
                         |
                         | SSH / Kubernetes API
                         |
          +--------------+--------------+
          |                             |
          v                             |
 +---------------------+                |
 |    control-plane    |                |
 |   192.168.252.2     |                |
 |                     |                |
 | Kubernetes API      |                |
 | Scheduler           |                |
 | Controller Manager  |                |
 | etcd                |                |
 |                     |                |
 | Calico node agent   |                |
 +---------------------+                |
          |                             |
          |    Multipass VM Network     |
          |    192.168.252.0/24         |
          |                             |
  +-------+----------------------+------+
  |                              |
  v                              v
+---------------------+  +---------------------+
|       worker-1      |  |       worker-2      |
|   192.168.252.3     |  |   192.168.252.4     |
|                     |  |                     |
| kubelet             |  | kubelet             |
| containerd          |  | containerd          |
| Calico node agent   |  | Calico node agent   |
|                     |  |                     |
| Pod networking      |  | Pod networking      |
+---------------------+  +---------------------+
          |                       |
          +-----------+-----------+
                      |
                Calico VXLAN
                      |
              Pod-to-Pod traffic

Pod network:     10.244.0.0/16
Service network: 10.96.0.0/12
```

Calico provides the Pod networking layer across all three nodes.

Kubernetes manages workload scheduling, Service abstractions, and cluster orchestration.

CoreDNS provides internal service discovery.

Calico enforces Kubernetes NetworkPolicies.

---

# 20. Final validation results

At the end of Phase 4, we obtained the following results.

| Component                    | Result                         |
| ---------------------------- | ------------------------------ |
| Kubernetes control plane     | Ready                          |
| worker-1                     | Ready                          |
| worker-2                     | Ready                          |
| Calico installation          | Operational                    |
| Pod IP allocation            | Functional                     |
| Cross-node Pod communication | Validated                      |
| Chrony synchronization       | Working on all three VMs       |
| Container image pulls        | Working after clock correction |
| Calico custom resources      | Idempotent                     |
| Tigera Operator deployment   | Idempotent                     |
| Phase 4 Ansible playbook     | `changed=0`, `failed=0`        |

The final Kubernetes version observed on all three nodes was:

```text
v1.35.9
```

The container runtime was:

```text
containerd://2.2.1
```

---

# 21. Remaining work — Full cluster reproducibility

Although the Phase 4 playbook is now idempotent, we still need to verify that the **entire Kubernetes environment can be recreated from scratch**.

This is different from executing the networking role against an existing cluster.

Our eventual objective is:

```text
Create VMs
    |
    v
Phase 2 — Prepare the operating systems
    |
    v
Phase 3 — Initialize Kubernetes
    |
    v
Phase 4 — Install Calico
    |
    v
Three-node Kubernetes cluster
```

Before performing this test, we must verify:

1. That all Phase 2 configurations, including Chrony verification, are committed to Git.
2. That the Phase 3 kubeadm configuration includes the required Kubernetes API server feature flags.
3. That node discovery, worker join commands, and kubeconfig retrieval can be performed after recreating the VMs.
4. That the Phase 4 role successfully installs Calico on a fresh cluster.
5. That rerunning the complete deployment does not produce unexpected changes.

Phase 1 Multipass VM creation must also be automated separately if we want to rebuild from absolutely nothing using a single command.

This full rebuild validation is a separate milestone and should be completed before treating the entire provisioning workflow as fully reproducible.

---

# 22. Files to preserve in Git

The most important Phase 4 files are:

```text
ansible/
├── files/
│   └── calico/
│       ├── v3_projectcalico_org-v1beta1.yaml
│       ├── tigera-operator.yaml
│       └── tigera-operator-normalized.yaml
│
├── roles/
│   ├── common/
│   │   └── tasks/
│   │       └── main.yml
│   │
│   └── calico/
│       ├── defaults/
│       │   └── main.yml
│       ├── tasks/
│       │   └── main.yml
│       └── templates/
│           └── custom-resources.yaml.j2
│
└── phase4-networking.yml
```

We should also preserve our networking test manifests, ideally under:

```text
tests/
└── networking/
    ├── networking-test.yaml
    └── deny-ingress.yaml
```

These tests can be executed again after deploying the cluster on AWS.

The Phase 3 kubeadm configuration must also be updated to preserve the API server feature flags required by this Calico version.

---

# 23. Conclusion

Phase 4 successfully transformed our previously initialized Kubernetes cluster into a network-enabled three-node environment.

We installed Calico using the Tigera Operator, configured VXLAN networking, enabled Pod IP allocation, and verified communication between Pods on different worker nodes.

We also investigated and resolved several operational problems:

- Kubernetes API compatibility with Calico admission policy resources.
- Incorrect system clocks preventing TLS certificate validation.
- Chrony running without initially being synchronized.
- Repeated Kubernetes resource updates caused by omitted default values.
- Repeated `kubectl apply` changes caused by empty fields in the Tigera Operator manifest.

The final Ansible playbook completes successfully with:

```text
changed=0
failed=0
unreachable=0
```

**Phase 4 is complete.**

Our base Kubernetes cluster is ready for the next part of the project: deploying and configuring the additional infrastructure components, including GitOps, observability, authentication, HTTPS, a private registry, and security controls.

Before those installations, we should complete the separate full-cluster rebuild validation to ensure that Phases 1–4 are truly reproducible from scratch.
