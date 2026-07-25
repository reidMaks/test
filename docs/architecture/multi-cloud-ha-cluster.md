# Multi-Cloud Highly Available Kubernetes Architecture (Talos Linux)

## 1. Concept & Vision
The goal is to build a fault-tolerant, hybrid-cloud Kubernetes cluster that seamlessly spans across an on-premise Proxmox environment (Home) and public cloud providers (Oracle Cloud and GCP). 

By leveraging **Talos Linux** and its built-in **KubeSpan** feature (WireGuard mesh network), nodes in completely different physical locations and networks will securely communicate as if they are on the same local switch.

This architecture ensures that if the Home environment is physically destroyed or loses power/internet, the cluster's Control Plane survives, and workloads can be automatically or manually spun up in Oracle Cloud without breaking the cluster state.

## 2. Control Plane Topology (The "Tiebreaker" Architecture)
Kubernetes `etcd` requires a strict majority (quorum) to function. Having an even number of Control Plane (CP) nodes (e.g., 2) is a critical anti-pattern that leads to split-brain scenarios and cluster freezing. We will use a mathematically perfect **3-node Control Plane** distributed across three data centers:

1. **Home CP (Proxmox)**: `cp_01` (Primary).
2. **Oracle CP (OCI)**: Ampere A1 (2 OCPU, 12GB RAM).
   * **Role:** Control Plane + Worker.
   * **Note:** Because this node is extremely powerful, we will remove the default `NoSchedule` taint by setting `allowSchedulingOnControlPlanes: true` in its Talos machine config, allowing it to run heavy workloads (Paperless, Tandoor, etc.).
3. **GCP CP (GCP)**: `e2-micro` (2 vCPU, 1GB RAM).
   * **Role:** Pure "Witness" / Tiebreaker node.
   * **Note:** This node exists **solely** to vote in `etcd` and maintain quorum (2 out of 3 votes). It will retain the `NoSchedule` taint to prevent Kubernetes from scheduling memory-intensive pods on it, preventing OOM crashes.

**Failover Scenarios:**
* **Home offline:** Oracle (1) + GCP (1) = 2/3 Quorum. Cluster survives.
* **Oracle offline:** Home (1) + GCP (1) = 2/3 Quorum. Cluster survives.
* **GCP offline:** Home (1) + Oracle (1) = 2/3 Quorum. Cluster survives.

## 3. Storage Strategy & Data Gravity
**WARNING:** Synchronous block storage replication (Longhorn) over a WAN connection (Internet) is strongly discouraged. The 40-60ms latency between Ukraine and Zurich will bottleneck disk IOPS, causing databases (PostgreSQL) to freeze or severely throttle.

* **Primary Storage:** Longhorn replicas should be restricted via Node Affinity to `location=home` nodes to maintain SSD-like performance.
* **Disaster Recovery (Offsite Backups):** Currently, Longhorn backs up to a local NAS (`192.168.0.21:8010`). This is a single point of failure. 
  * **Action Required:** Provision a free cloud S3 bucket (Oracle Object Storage 10GB free, or Cloudflare R2). Configure Longhorn to push hourly/daily backups to this Cloud S3. 
* **If Home fails:** The Oracle node will still be alive. You can trigger a Longhorn Volume Restoration from the Cloud S3 bucket directly into the Oracle node to resume operations.

## 4. Implementation Steps (When Home Hardware is Accessible)

### Step 1: Offsite Backup Migration
* Create an S3 Bucket on Cloudflare R2 or Oracle Object Storage.
* Update your Bitwarden secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) to point to the new Cloud S3 bucket.
* Update `infrastructure.tf` to point Longhorn `backupTarget` to the new S3 bucket and apply. Ensure a successful backup is completed.

### Step 2: Cloud Infrastructure Provisioning
* Expand your Terraform `infra` directory (or create a new combined state) to include `oci_core_instance` and `google_compute_instance`.
* Boot both cloud instances using the official **Talos Linux Cloud Images** (GCP has a native image, OCI requires custom image import or iPXE boot).

### Step 3: Talos Configuration & KubeSpan
* Update `talos.tf` to include the two new cloud nodes in the `machine_configuration`.
* **Crucial Patch:** Inject the following patch into ALL machine configurations (Home, Oracle, GCP) to enable the automatic WireGuard mesh:
  ```yaml
  machine:
    features:
      kubespan: true
  ```
* For the Oracle node, patch the cluster config:
  ```yaml
  cluster:
    allowSchedulingOnControlPlanes: true
  ```
* For the GCP node, ensure it remains a pure control plane.

### Step 4: Apply & Bootstrap
* Apply the Terraform state. Talos will apply the configurations.
* Due to KubeSpan, the nodes will automatically discover each other using WireGuard and form a single unified cluster.

### Step 5: Workload Routing
* Rely on your existing **Cloudflare Tunnels** (`cloudflared`). Because Cloudflare tunnels establish outbound connections from within the cluster pods, traffic will automatically reach your web services regardless of whether they are physically running on a Home worker or the Oracle node. No public IP management or port forwarding is required.
