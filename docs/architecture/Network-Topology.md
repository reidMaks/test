# Network Topology

```mermaid
flowchart TD
    subgraph Users
        F[Family / Public]
        A[Admin / Mobile VPN]
        R[Home Router]
    end

    subgraph OCI Cloud
        CP2[talos_oci CP]
        CP3[talos_oci_2 CP]
        WG[WG Hub Pod (on CP2)]
    end

    subgraph Home Proxmox
        CP1[cp_01 CP]
        W1[worker_01]
        W2[worker_02]

        subgraph Kubernetes Ingress
            CF[Cloudflared Pod]
            TR[Traefik Ingress]
            MLB[MetalLB 192.168.0.45]
        end

        APPS[K8s Workloads e.g. Tandoor]
    end

    subgraph QNAP NAS
        QNAP_TR[Traefik QNAP]
        ARR[Arr-Stack / Jellyfin]
        PORT[Portainer]
    end

    %% Connections
    F -->|HTTPS| Cloudflare[(Cloudflare Edge)]
    Cloudflare <-->|Tunnel| CF
    CF --> TR

    A -->|UDP 51821| WG
    R -->|UDP 51821| WG
    WG -->|socat Proxy| TR

    MLB --- TR
    TR --> APPS

    R -->|Local DNS *.home.arpa| QNAP_TR
    QNAP_TR --> ARR
    QNAP_TR --> PORT
    QNAP_TR -.->|Proxy| Home_PVE[Proxmox VE Admin]

    %% KubeSpan
    CP1 -.->|KubeSpan| CP2
    CP1 -.->|KubeSpan| CP3
    W1 -.->|KubeSpan| CP2
    W2 -.->|KubeSpan| CP3
```
