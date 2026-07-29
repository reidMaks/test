# ADR 005: QNAP Internal DNS and Traefik Aliasing

## Context
Services running on the QNAP NAS via Docker Compose (like Seerr, Sonarr, Radarr) often need to communicate with other services on the same host (like Jellyfin). While they can use direct Docker container names (e.g., `http://jellyfin:8096`), some applications like Seerr expose these URLs to the end user UI (e.g., "Play on Jellyfin" buttons). If internal container names are used, these buttons break for external clients.
However, if external `.home.arpa` domains are used, the internal Docker containers fail to resolve them if the upstream DNS server (the local router) lacks the necessary NAT loopback or DNS entries.

## Decision
1. **Remove hardcoded `dns` overrides**: Hardcoded `dns: - 192.168.0.1` entries have been removed from the Docker Compose configurations in `qnap/portainer/docker-compose.yml`. This allows the containers to use Docker's embedded internal DNS (`127.0.0.11`) for resolving requests on the custom `proxy` network.
2. **Network Aliasing on Traefik**: To allow internal services to resolve `.home.arpa` domains without external router configuration, network aliases (e.g., `jellyfin.home.arpa`, `seerr.home.arpa`) are assigned directly to the `traefik-qnap` container in `qnap/traefik/docker-compose.yml`.

When a container looks up `jellyfin.home.arpa`, Docker's internal DNS routes it to the `traefik-qnap` container's internal IP. Traefik then processes the request (including HTTPS redirection) and proxies it to the appropriate backend service.

## Consequences
- **Pros**:
  - Containers can use external-facing domains (`.home.arpa`) for API connections.
  - UI links in services like Seerr remain functional for end users.
  - Traffic stays entirely within the Docker `proxy` network, reducing latency and bypassing the external router.
- **Cons**:
  - Connections to `.home.arpa` via HTTPS internally may require ignoring self-signed certificate errors (e.g., `NODE_TLS_REJECT_UNAUTHORIZED=0` for Node.js apps) if Traefik uses a self-signed cert for local domains.
