#!/usr/bin/env python3
"""
arr-configurator: Media Stack Infrastructure as Code & Drift Reconciliation
Ensures running infrastructure strictly matches the declared state in Git:
1. Reconciles configuration files against templates (detects drift, creates .bak, updates in-place).
2. Reconciles service connections via REST APIs (ensures download clients, indexer sync, and Seerr match code).
"""

import os
import sys
import time
import json
import logging
import argparse
import urllib.request
import urllib.error
from string import Template

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("arr-configurator")

TEMPLATES = [
    ("cross-seed/config.js.template", "cross-seed/config.js"),
    ("qbittorrent/qBittorrent.conf.template", "qbittorrent/qBittorrent/qBittorrent.conf"),
    ("sonarr/config.xml.template", "sonarr/config.xml"),
    ("radarr/config.xml.template", "radarr/config.xml"),
    ("prowlarr/config.xml.template", "prowlarr/config.xml"),
    ("lidarr/config.xml.template", "lidarr/config.xml"),
    ("seerr/settings.json.template", "seerr/settings.json"),
]

def reconcile_templates(template_dir: str, config_dir: str):
    """
    Reconciles target configuration files with code templates.
    If the file exists but has drifted from the code, it backs it up and applies the code state.
    """
    logger.info("== Phase 1: Reconciling configuration files against code templates ==")

    for tpl_rel, dst_rel in TEMPLATES:
        tpl_path = os.path.join(template_dir, tpl_rel)
        dst_path = os.path.join(config_dir, dst_rel)

        if not os.path.exists(tpl_path):
            logger.warning(f"  [WARN] Template not found: {tpl_path}, skipping.")
            continue

        try:
            with open(tpl_path, "r", encoding="utf-8") as f:
                raw_content = f.read()

            rendered = Template(raw_content).safe_substitute(os.environ)

            if os.path.exists(dst_path):
                with open(dst_path, "r", encoding="utf-8") as f:
                    current_content = f.read()

                # Normalize line endings for fair comparison
                if current_content.strip() == rendered.strip():
                    logger.info(f"  [IN_SYNC] {dst_rel} strictly matches desired code state.")
                    continue

                # Drift detected! Update target file to match code
                backup_path = f"{dst_path}.bak"
                with open(backup_path, "w", encoding="utf-8") as f:
                    f.write(current_content)
                logger.info(f"  [DRIFT DETECTED] {dst_rel} differs from code. Backup saved to {dst_rel}.bak")

            os.makedirs(os.path.dirname(dst_path), exist_ok=True)
            with open(dst_path, "w", encoding="utf-8") as f:
                f.write(rendered)

            logger.info(f"  [RECONCILED] Applied desired code configuration to {dst_rel}.")
        except Exception as e:
            logger.error(f"  [FAIL] Error reconciling {dst_rel}: {e}")

def reconcile_seerr_config(config_dir: str):
    """Enforces declarative settings on Seerr configuration."""
    seerr_settings = os.path.join(config_dir, "seerr", "settings.json")
    if not os.path.exists(seerr_settings):
        return

    try:
        with open(seerr_settings, "r", encoding="utf-8") as f:
            data = json.load(f)

        modified = False
        # Enforce Radarr baseUrl and hostname
        if "radarr" in data and isinstance(data["radarr"], list):
            for radarr in data["radarr"]:
                if radarr.get("baseUrl") != "" or radarr.get("hostname") != "radarr":
                    radarr["baseUrl"] = ""
                    radarr["hostname"] = "radarr"
                    radarr["port"] = 80
                    radarr["useSsl"] = False
                    modified = True
                    logger.info("  [RECONCILE] Enforced clean baseUrl and hostname for Radarr in Seerr.")

        # Enforce Sonarr baseUrl and hostname
        if "sonarr" in data and isinstance(data["sonarr"], list):
            for sonarr in data["sonarr"]:
                if sonarr.get("baseUrl") != "" or sonarr.get("hostname") != "sonarr":
                    sonarr["baseUrl"] = ""
                    sonarr["hostname"] = "sonarr"
                    sonarr["port"] = 80
                    sonarr["useSsl"] = False
                    modified = True
                    logger.info("  [RECONCILE] Enforced clean baseUrl and hostname for Sonarr in Seerr.")

        # Enforce Jellyfin direct internal networking
        if "jellyfin" in data and isinstance(data["jellyfin"], dict):
            jf = data["jellyfin"]
            if jf.get("ip") != "jellyfin" or jf.get("port") != 8096 or jf.get("useSsl") is not False:
                jf["ip"] = "jellyfin"
                jf["port"] = 8096
                jf["useSsl"] = False
                jf["urlBase"] = ""
                modified = True
                logger.info("  [RECONCILE] Enforced direct internal networking for Jellyfin in Seerr.")

        if modified:
            with open(seerr_settings, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=1)
            logger.info("  [SAVED] Seerr settings reconciled with code.")
    except Exception as e:
        logger.warning(f"Could not reconcile Seerr settings: {e}")

def wait_for_api(url: str, timeout: int = 30) -> bool:
    """Waits for an API endpoint to become reachable."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "arr-configurator"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status in (200, 401):
                    return True
        except:
            time.sleep(2)
    return False

def api_request(url: str, method: str = "GET", data: dict = None, headers: dict = None):
    """Helper to perform JSON API calls."""
    hdrs = {"User-Agent": "arr-configurator", "Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    payload = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=payload, headers=hdrs, method=method)
    with urllib.request.urlopen(req, timeout=10) as resp:
        content = resp.read().decode("utf-8")
        return json.loads(content) if content else {}

def reconcile_download_client(service_name: str, base_url: str, api_key: str, category_name: str, qb_user: str, qb_pass: str):
    """Ensures qBittorrent download client is present and accurately configured."""
    url = f"{base_url}/api/v3/downloadclient?apikey={api_key}"
    try:
        clients = api_request(url)
        existing = next((c for c in clients if "qbittorrent" in c.get("implementation", "").lower()), None)

        expected_fields = [
            {"name": "host", "value": "qbittorrent"},
            {"name": "port", "value": 8085},
            {"name": "useSsl", "value": False},
            {"name": "username", "value": qb_user},
            {"name": "password", "value": qb_pass},
            {"name": "tvCategory" if "sonarr" in service_name.lower() else "movieCategory", "value": category_name}
        ]

        if not existing:
            logger.info(f"  [CREATE] Adding qBittorrent download client to {service_name}...")
            payload = {
                "enable": True,
                "protocol": "torrent",
                "priority": 1,
                "name": "qBittorrent",
                "implementation": "QBittorrent",
                "configContract": "QBittorrentSettings",
                "fields": expected_fields
            }
            api_request(url, method="POST", data=payload)
            logger.info(f"  [DONE] Created qBittorrent download client in {service_name}.")
        else:
            # Check for drift in existing settings
            current_fields = {f.get("name"): f.get("value") for f in existing.get("fields", [])}
            needs_update = False
            for exp in expected_fields:
                if current_fields.get(exp["name"]) != exp["value"]:
                    needs_update = True
                    break

            if needs_update:
                logger.info(f"  [DRIFT DETECTED] qBittorrent settings drifted in {service_name}. Updating...")
                existing["fields"] = expected_fields
                api_request(f"{base_url}/api/v3/downloadclient/{existing['id']}?apikey={api_key}", method="PUT", data=existing)
                logger.info(f"  [RECONCILED] Updated qBittorrent download client in {service_name}.")
            else:
                logger.info(f"  [IN_SYNC] qBittorrent download client in {service_name} matches code.")
    except Exception as e:
        logger.warning(f"  [WARN] Could not reconcile download client in {service_name}: {e}")

def reconcile_prowlarr_apps(prowlarr_key: str, sonarr_key: str, radarr_key: str):
    """Ensures Prowlarr application sync is in sync with declared services."""
    url = f"http://prowlarr:80/api/v1/applications?apikey={prowlarr_key}"
    try:
        apps = api_request(url)
        app_map = {a.get("name", "").lower(): a for a in apps}

        targets = [
            ("Sonarr", "http://sonarr:80", sonarr_key, "SonarrSettings"),
            ("Radarr", "http://radarr:80", radarr_key, "RadarrSettings"),
        ]

        for name, svc_url, key, contract in targets:
            if not key:
                continue
            existing = app_map.get(name.lower())
            expected_fields = [
                {"name": "prowlarrUrl", "value": "http://prowlarr:80"},
                {"name": "baseUrl", "value": svc_url},
                {"name": "apiKey", "value": key}
            ]

            if not existing:
                logger.info(f"  [CREATE] Linking {name} to Prowlarr for indexer sync...")
                payload = {
                    "name": name,
                    "syncLevel": "fullSync",
                    "implementation": name,
                    "configContract": contract,
                    "fields": expected_fields
                }
                api_request(url, method="POST", data=payload)
                logger.info(f"  [DONE] {name} linked in Prowlarr.")
            else:
                curr_fields = {f.get("name"): f.get("value") for f in existing.get("fields", [])}
                if curr_fields.get("apiKey") != key or curr_fields.get("baseUrl") != svc_url:
                    logger.info(f"  [DRIFT DETECTED] {name} settings in Prowlarr drifted. Reconciling...")
                    existing["fields"] = expected_fields
                    api_request(f"{url}/{existing['id']}?apikey={prowlarr_key}", method="PUT", data=existing)
                    logger.info(f"  [RECONCILED] Updated {name} in Prowlarr.")
                else:
                    logger.info(f"  [IN_SYNC] {name} integration in Prowlarr matches code.")
    except Exception as e:
        logger.warning(f"  [WARN] Could not reconcile Prowlarr applications: {e}")

def auto_wire_services():
    """Performs full REST API reconciliation."""
    logger.info("== Phase 2: Reconciling service integrations via REST APIs ==")

    sonarr_key = os.environ.get("SONARR_API_KEY", "")
    radarr_key = os.environ.get("RADARR_API_KEY", "")
    prowlarr_key = os.environ.get("PROWLARR_API_KEY", "")
    qb_user = os.environ.get("QBITTORRENT_USER", "admin")
    qb_pass = os.environ.get("QBITTORRENT_PASSWORD", "")

    # Reconcile Sonarr download client
    if sonarr_key and wait_for_api("http://sonarr:80/api/v3/system/status?apikey=" + sonarr_key, 10):
        reconcile_download_client("Sonarr", "http://sonarr:80", sonarr_key, "tv-sonarr", qb_user, qb_pass)

    # Reconcile Radarr download client
    if radarr_key and wait_for_api("http://radarr:80/api/v3/system/status?apikey=" + radarr_key, 10):
        reconcile_download_client("Radarr", "http://radarr:80", radarr_key, "radarr", qb_user, qb_pass)

    # Reconcile Prowlarr applications
    if prowlarr_key and wait_for_api("http://prowlarr:80/api/v1/system/status?apikey=" + prowlarr_key, 10):
        reconcile_prowlarr_apps(prowlarr_key, sonarr_key, radarr_key)

def main():
    parser = argparse.ArgumentParser(description="arr-configurator: Media Stack Infrastructure as Code & Drift Reconciliation")
    parser.add_argument("--template-dir", default="/templates", help="Path to config templates")
    parser.add_argument("--config-dir", default="/config", help="Path to /config mount")
    parser.add_argument("--phase", choices=["init", "wire", "all"], default="all", help="Execution phase")
    args = parser.parse_args()

    logger.info("Starting Media Stack Infrastructure as Code Reconciliation...")

    if args.phase in ("init", "all"):
        reconcile_templates(args.template_dir, args.config_dir)
        reconcile_seerr_config(args.config_dir)

    if args.phase in ("wire", "all"):
        auto_wire_services()

    logger.info("Reconciliation completed successfully! Infrastructure strictly matches code.")

if __name__ == "__main__":
    main()
