# ADR 006: QNAP Local CA and TLS Configuration

## Context & Problem
All services hosted on the QNAP NAS (Jellyfin, Seerr, Arr-stack) are exposed via Traefik over HTTPS on the `.home.arpa` internal domain. Using default self-signed certificates caused persistent issues:
1. Modern browsers (Chrome, Safari, iOS/macOS) do not allow permanent trust exceptions for standard self-signed certificates.
2. Browsers enforce strict requirements: TLS certificates must be valid for no more than 398 days.
3. Chrome sometimes rejects wildcard certificates (`*.home.arpa`) with `ERR_CERT_COMMON_NAME_INVALID` because `.home.arpa` can be treated similarly to a Public Suffix, requiring explicit Subject Alternative Names (SANs).
4. Some mobile apps (like iOS qBittorrent controllers) cannot ignore certificate errors and refuse to connect over HTTPS.

## Decisions

### 1. Automated Local Root CA
Instead of manually managing certificates or maintaining a complex external PKI, the `traefik-configurator` container (defined in `qnap/traefik/docker-compose.yml`) was updated to automatically bootstrap a Local Root CA.
- On startup, it checks for existing certificates.
- If none exist, it installs `openssl` and generates a 10-year `local-ca.crt`.
- It then generates a leaf certificate (`home-arpa.crt`) signed by this Local CA.

### 2. Browser Compliance (398 days & Explicit SANs)
To satisfy Chrome and Apple's strict security policies:
- The leaf certificate is generated with a strict **398-day validity**.
- An `extfile.cnf` is generated dynamically to include **explicit SANs** for every known service (e.g., `DNS:seerr.home.arpa, DNS:jellyfin.home.arpa, DNS:qb.home.arpa`), alongside the `*.home.arpa` wildcard.

### 3. Direct Port Exposure for Legacy/Mobile Apps
For applications that cannot process custom CAs (e.g., the iOS qBittorrent app), Traefik's global HTTP-to-HTTPS redirect prevents standard HTTP usage. To resolve this, specific services like qBittorrent expose their ports directly to the QNAP host (`8085:8085`). Clients can connect to `http://<qnap-ip>:8085` to completely bypass Traefik and its TLS requirements.

## Operational Guide
To trust the endpoints on client devices (macOS, iOS, Windows, Linux), the user must extract the generated `local-ca.crt` from the QNAP and install it into their system's Root Trust Store.

**Extraction command:**
```bash
ssh qnap "sh -lc 'docker cp traefik-configurator:/conf/certs/local-ca.crt -'" > ~/local-ca.crt
```

**Linux Installation (System-wide):**
```bash
sudo cp ~/local-ca.crt /usr/local/share/ca-certificates/home-local-ca.crt
sudo update-ca-certificates
```
*(Note: Browsers like Firefox and Chrome using NSS may require manual import via settings or `certutil`).*
