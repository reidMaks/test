#!/usr/bin/env python3
"""
arr-configurator: Media Stack Infrastructure as Code Bootstrapper
Handles:
1. Safe template rendering for fresh environments without overwriting existing configs.
2. REST API auto-wiring between qBittorrent, Prowlarr, Sonarr, Radarr, Lidarr, and Seerr.
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

# Template to target mappings relative to (template_dir, config_dir)
TEMPLATES = [
    ("cross-seed/config.js.template", "cross-seed/config.js"),
    ("qbittorrent/qBittorrent.conf.template", "qbittorrent/qBittorrent/qBittorrent.conf"),
    ("sonarr/config.xml.template", "sonarr/config.xml"),
    ("radarr/config.xml.template", "radarr/config.xml"),
    ("prowlarr/config.xml.template", "prowlarr/config.xml"),
    ("lidarr/config.xml.template", "lidarr/config.xml"),
    ("seerr/settings.json.template", "seerr/settings.json"),
]

def render_templates(template_dir: str, config_dir: str, force: bool = False):
    """Renders configuration templates using environment variables safely."""
    logger.info("== Phase 1: Checking configuration files ==")

    for tpl_rel, dst_rel in TEMPLATES:
        tpl_path = os.path.join(template_dir, tpl_rel)
        dst_path = os.path.join(config_dir, dst_rel)

        if not os.path.exists(tpl_path):
            logger.warning(f"Template not found: {tpl_path}, skipping.")
            continue

        if os.path.exists(dst_path) and not force:
            logger.info(f"  [SKIP] {dst_rel} already exists. Preserving existing configuration.")
            continue

        try:
            with open(tpl_path, "r", encoding="utf-8") as f:
                raw_content = f.read()

            # Safely substitute environment variables
            rendered = Template(raw_content).safe_substitute(os.environ)

            os.makedirs(os.path.dirname(dst_path), exist_ok=True)
            with open(dst_path, "w", encoding="utf-8") as f:
                f.write(rendered)

            logger.info(f"  [INIT] Rendered {dst_rel} successfully from template.")
        except Exception as e:
            logger.error(f"  [FAIL] Error rendering {dst_rel}: {e}")

def fix_seerr_config(config_dir: str):
    """Automatically fixes known configuration discrepancies in Seerr if present."""
    seerr_settings = os.path.join(config_dir, "seerr", "settings.json")
    if not os.path.exists(seerr_settings):
        return

    try:
        with open(seerr_settings, "r", encoding="utf-8") as f:
            data = json.load(f)

        modified = False
        # Fix Radarr baseUrl / hostname in Seerr
        if "radarr" in data and isinstance(data["radarr"], list):
            for radarr in data["radarr"]:
                if radarr.get("baseUrl") == "/radarr.home.arpa":
                    radarr["baseUrl"] = ""
                    radarr["hostname"] = "radarr"
                    modified = True
                    logger.info("  [FIX] Corrected Radarr baseUrl in Seerr settings.")

        # Fix Sonarr baseUrl / hostname in Seerr
        if "sonarr" in data and isinstance(data["sonarr"], list):
            for sonarr in data["sonarr"]:
                if sonarr.get("baseUrl") == "/sonarr.home.arpa":
                    sonarr["baseUrl"] = ""
                    sonarr["hostname"] = "sonarr"
                    modified = True
                    logger.info("  [FIX] Corrected Sonarr baseUrl in Seerr settings.")

        if modified:
            with open(seerr_settings, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=1)
            logger.info("  [SAVED] Seerr settings updated and saved.")
    except Exception as e:
        logger.warning(f"Could not verify Seerr settings: {e}")

def wait_for_api(url: str, timeout: int = 30) -> bool:
    """Waits for an API endpoint to become reachable."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "arr-configurator"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status in (200, 401):  # 401 means server is up and listening
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
        return json.loads(resp.read().decode("utf-8"))

def auto_wire_services():
    """Connects download clients and application sync via REST APIs."""
    logger.info("== Phase 2: Verifying & Auto-wiring service integrations ==")

    sonarr_key = os.environ.get("SONARR_API_KEY", "")
    radarr_key = os.environ.get("RADARR_API_KEY", "")
    prowlarr_key = os.environ.get("PROWLARR_API_KEY", "")
    qb_user = os.environ.get("QBITTORRENT_USER", "admin")
    qb_pass = os.environ.get("QBITTORRENT_PASSWORD", "")

    # 1. Wire qBittorrent into Sonarr
    if sonarr_key and wait_for_api("http://sonarr:80/api/v3/system/status?apikey=" + sonarr_key, 10):
        try:
            clients = api_request(f"http://sonarr:80/api/v3/downloadclient?apikey={sonarr_key}")
            has_qb = any("qbittorrent" in c.get("implementation", "").lower() for c in clients)
            if not has_qb:
                logger.info("  [WIRE] Adding qBittorrent download client to Sonarr...")
                qb_payload = {
                    "enable": True,
                    "protocol": "torrent",
                    "priority": 1,
                    "name": "qBittorrent",
                    "implementation": "QBittorrent",
                    "configContract": "QBittorrentSettings",
                    "fields": [
                        {"name": "host", "value": "qbittorrent"},
                        {"name": "port", "value": 8085},
                        {"name": "useSsl", "value": False},
                        {"name": "username", "value": qb_user},
                        {"name": "password", "value": qb_pass},
                        {"name": "tvCategory", "value": "tv-sonarr"}
                    ]
                }
                api_request(f"http://sonarr:80/api/v3/downloadclient?apikey={sonarr_key}", method="POST", data=qb_payload)
                logger.info("  [DONE] qBittorrent linked to Sonarr.")
            else:
                logger.info("  [OK] qBittorrent download client already configured in Sonarr.")
        except Exception as e:
            logger.warning(f"  [WARN] Could not verify Sonarr download client: {e}")

    # 2. Wire qBittorrent into Radarr
    if radarr_key and wait_for_api("http://radarr:80/api/v3/system/status?apikey=" + radarr_key, 10):
        try:
            clients = api_request(f"http://radarr:80/api/v3/downloadclient?apikey={radarr_key}")
            has_qb = any("qbittorrent" in c.get("implementation", "").lower() for c in clients)
            if not has_qb:
                logger.info("  [WIRE] Adding qBittorrent download client to Radarr...")
                qb_payload = {
                    "enable": True,
                    "protocol": "torrent",
                    "priority": 1,
                    "name": "qBittorrent",
                    "implementation": "QBittorrent",
                    "configContract": "QBittorrentSettings",
                    "fields": [
                        {"name": "host", "value": "qbittorrent"},
                        {"name": "port", "value": 8085},
                        {"name": "useSsl", "value": False},
                        {"name": "username", "value": qb_user},
                        {"name": "password", "value": qb_pass},
                        {"name": "movieCategory", "value": "radarr"}
                    ]
                }
                api_request(f"http://radarr:80/api/v3/downloadclient?apikey={radarr_key}", method="POST", data=qb_payload)
                logger.info("  [DONE] qBittorrent linked to Radarr.")
            else:
                logger.info("  [OK] qBittorrent download client already configured in Radarr.")
        except Exception as e:
            logger.warning(f"  [WARN] Could not verify Radarr download client: {e}")

    # 3. Wire Sonarr & Radarr into Prowlarr
    if prowlarr_key and wait_for_api("http://prowlarr:80/api/v1/system/status?apikey=" + prowlarr_key, 10):
        try:
            apps = api_request(f"http://prowlarr:80/api/v1/applications?apikey={prowlarr_key}")
            names = [a.get("name", "").lower() for a in apps]

            if "sonarr" not in names and sonarr_key:
                logger.info("  [WIRE] Linking Sonarr to Prowlarr for indexer sync...")
                app_payload = {
                    "name": "Sonarr",
                    "syncLevel": "fullSync",
                    "implementation": "Sonarr",
                    "configContract": "SonarrSettings",
                    "fields": [
                        {"name": "prowlarrUrl", "value": "http://prowlarr:80"},
                        {"name": "baseUrl", "value": "http://sonarr:80"},
                        {"name": "apiKey", "value": sonarr_key}
                    ]
                }
                api_request(f"http://prowlarr:80/api/v1/applications?apikey={prowlarr_key}", method="POST", data=app_payload)
                logger.info("  [DONE] Sonarr linked in Prowlarr.")

            if "radarr" not in names and radarr_key:
                logger.info("  [WIRE] Linking Radarr to Prowlarr for indexer sync...")
                app_payload = {
                    "name": "Radarr",
                    "syncLevel": "fullSync",
                    "implementation": "Radarr",
                    "configContract": "RadarrSettings",
                    "fields": [
                        {"name": "prowlarrUrl", "value": "http://prowlarr:80"},
                        {"name": "baseUrl", "value": "http://radarr:80"},
                        {"name": "apiKey", "value": radarr_key}
                    ]
                }
                api_request(f"http://prowlarr:80/api/v1/applications?apikey={prowlarr_key}", method="POST", data=app_payload)
                logger.info("  [DONE] Radarr linked in Prowlarr.")

            logger.info("  [OK] Prowlarr applications verified.")
        except Exception as e:
            logger.warning(f"  [WARN] Could not verify Prowlarr applications: {e}")

def main():
    parser = argparse.ArgumentParser(description="arr-configurator: Media Stack Infrastructure as Code")
    parser.add_argument("--template-dir", default="/templates", help="Path to config templates")
    parser.add_argument("--config-dir", default="/config", help="Path to /config mount")
    parser.add_argument("--force", action="store_true", help="Force overwrite existing configuration files")
    parser.add_argument("--phase", choices=["init", "wire", "all"], default="all", help="Execution phase")
    args = parser.parse_args()

    logger.info("Starting Media Stack Infrastructure Configurator...")

    if args.phase in ("init", "all"):
        render_templates(args.template_dir, args.config_dir, force=args.force)
        fix_seerr_config(args.config_dir)

    if args.phase in ("wire", "all"):
        auto_wire_services()

    logger.info("All configurator tasks completed successfully!")

if __name__ == "__main__":
    main()
