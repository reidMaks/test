#!/bin/bash
set -e

# Update and install dependencies
apt-get update
apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Compose plugin
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Setup directories for the app
APP_DIR="/opt/actualbudget"
mkdir -p "$APP_DIR/certs"
mkdir -p "$APP_DIR/data"
mkdir -p "$APP_DIR/caddy_data"
mkdir -p "$APP_DIR/caddy_config"

# Set ownership of data directory to UID 1000 (Actual Budget default user)
chown -R 1000:1000 "$APP_DIR/data"

# Write application files (decoded from base64 injected by Terraform)
echo "${docker_compose_b64}" | base64 -d > "$APP_DIR/docker-compose.yml"
echo "${caddyfile_b64}" | base64 -d > "$APP_DIR/Caddyfile"
echo "${addon_py_b64}" | base64 -d > "$APP_DIR/addon.py"

# Write the .env file with the secret token
cat << 'EOF' > "$APP_DIR/.env"
MONOBANK_TOKEN=${monobank_token}
EOF

# Ensure correct permissions
chmod 600 "$APP_DIR/.env"

# Pre-generate mitmproxy certificate to prevent race condition where actual-server
# starts and tries to read the cert before mitmproxy has finished generating it.
if [ ! -f "$APP_DIR/certs/mitmproxy-ca-cert.pem" ]; then
  docker run --rm -v "$APP_DIR/certs:/certs" --user root mitmproxy/mitmproxy:10.1.6 bash -c "mitmdump --set confdir=/certs & sleep 3; kill \$!"
fi

# Start the application
cd "$APP_DIR"
docker compose up -d
test
