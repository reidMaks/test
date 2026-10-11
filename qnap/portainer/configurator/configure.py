#!/usr/bin/env python3
"""
arr-configurator: Media Stack Infrastructure as Code & Drift Reconciliation
Ensures running infrastructure strictly matches the declared state in Git.

Safety Behavior:
- If configuration drift is detected, arr-configurator logs unified diffs and raises
  a DriftDetectedError by default, aborting execution to prevent accidental data loss.
- To enforce code state over running infrastructure, pass --overwrite-drift or set
  OVERWRITE_DRIFT=true in .env.
"""

import os
import sys
import time
import json
import difflib
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

class DriftDetectedError(Exception):
    """Raised when configuration drift is detected and overwrite is not explicitly authorized."""
    pass

TEMPLATES = [
    ("cross-seed/config.js.template", "cross-seed/config.js"),
    ("qbittorrent/qBittorrent.conf.template", "qbittorrent/qBittorrent/qBittorrent.conf"),
    ("sonarr/config.xml.template", "sonarr/config.xml"),
    ("radarr/config.xml.template", "radarr/config.xml"),
    ("prowlarr/config.xml.template", "prowlarr/config.xml"),
    ("lidarr/config.xml.template", "lidarr/config.xml"),
    ("bazarr/config.yaml.template", "bazarr/config/config.yaml"),
    ("jellyfin/network.xml.template", "jellyfin/network.xml"),
    ("jellyfin/system.xml.template", "jellyfin/system.xml"),
    ("jellyfin/encoding.xml.template", "jellyfin/encoding.xml"),
    ("seerr/settings.json.template", "seerr/settings.json"),
]

def reconcile_templates(template_dir: str, config_dir: str, allow_overwrite: bool = False) -> list[str]:
    """
    Checks target configuration files against rendered code templates.
    If drift is detected, logs the unified diff and either reports it as an error or overwrites.
    """
    drifts = []
    logger.info("== Phase 1: Checking & Reconciling configuration files ==")

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

            if not os.path.exists(dst_path):
                # Initial bootstrapping
                os.makedirs(os.path.dirname(dst_path), exist_ok=True)
                with open(dst_path, "w", encoding="utf-8") as f:
                    f.write(rendered)
                logger.info(f"  [BOOTSTRAP] Written initial configuration for {dst_rel}.")
                continue

            with open(dst_path, "r", encoding="utf-8") as f:
                current_content = f.read()

            # Normalize line endings for fair comparison
            if current_content.strip() == rendered.strip():
                logger.info(f"  [IN_SYNC] {dst_rel} strictly matches desired code state.")
                continue

            # Drift detected!
            diff = list(difflib.unified_diff(
                current_content.splitlines(keepends=True),
                rendered.splitlines(keepends=True),
                fromfile=f"disk:{dst_rel}",
                tofile=f"repo:{tpl_rel}"
            ))
            diff_str = "".join(diff)
            logger.warning(f"  [DRIFT DETECTED] {dst_rel} differs from declared template:\n{diff_str}")

            if not allow_overwrite:
                drifts.append(f"File drift in {dst_rel}")
            else:
                backup_path = f"{dst_path}.bak"
                with open(backup_path, "w", encoding="utf-8") as f:
                    f.write(current_content)
                with open(dst_path, "w", encoding="utf-8") as f:
                    f.write(rendered)
                logger.info(f"  [OVERWRITTEN] Applied desired code to {dst_rel} (backup saved to {dst_rel}.bak).")
        except Exception as e:
            logger.error(f"  [FAIL] Error processing {dst_rel}: {e}")
            drifts.append(f"Error checking {dst_rel}: {e}")

    return drifts

def reconcile_seerr_config(config_dir: str, allow_overwrite: bool = False) -> list[str]:
    """Checks and reconciles declarative settings on Seerr configuration."""
    drifts = []
    seerr_settings = os.path.join(config_dir, "seerr", "settings.json")
    if not os.path.exists(seerr_settings):
        return drifts

    try:
        with open(seerr_settings, "r", encoding="utf-8") as f:
            data = json.load(f)

        modified = False
        # Check Radarr baseUrl and hostname
        if "radarr" in data and isinstance(data["radarr"], list):
            for radarr in data["radarr"]:
                if radarr.get("baseUrl") != "" or radarr.get("hostname") != "radarr":
                    diff_msg = f"Seerr Radarr setting drift: hostname='{radarr.get('hostname')}' (expected 'radarr'), baseUrl='{radarr.get('baseUrl')}' (expected '')"
                    logger.warning(f"  [DRIFT DETECTED] {diff_msg}")
                    if not allow_overwrite:
                        drifts.append(diff_msg)
                    else:
                        radarr["baseUrl"] = ""
                        radarr["hostname"] = "radarr"
                        radarr["port"] = 80
                        radarr["useSsl"] = False
                        modified = True

        # Check Sonarr baseUrl and hostname
        if "sonarr" in data and isinstance(data["sonarr"], list):
            for sonarr in data["sonarr"]:
                if sonarr.get("baseUrl") != "" or sonarr.get("hostname") != "sonarr":
                    diff_msg = f"Seerr Sonarr setting drift: hostname='{sonarr.get('hostname')}' (expected 'sonarr'), baseUrl='{sonarr.get('baseUrl')}' (expected '')"
                    logger.warning(f"  [DRIFT DETECTED] {diff_msg}")
                    if not allow_overwrite:
                        drifts.append(diff_msg)
                    else:
                        sonarr["baseUrl"] = ""
                        sonarr["hostname"] = "sonarr"
                        sonarr["port"] = 80
                        sonarr["useSsl"] = False
                        modified = True

        # Check Jellyfin direct internal networking
        if "jellyfin" in data and isinstance(data["jellyfin"], dict):
            jf = data["jellyfin"]
            if jf.get("ip") != "jellyfin" or jf.get("port") != 8096 or jf.get("useSsl") is not False:
                diff_msg = f"Seerr Jellyfin setting drift: ip='{jf.get('ip')}' (expected 'jellyfin'), port={jf.get('port')} (expected 8096)"
                logger.warning(f"  [DRIFT DETECTED] {diff_msg}")
                if not allow_overwrite:
                    drifts.append(diff_msg)
                else:
                    jf["ip"] = "jellyfin"
                    jf["port"] = 8096
                    jf["useSsl"] = False
                    jf["urlBase"] = ""
                    modified = True

        if modified and allow_overwrite:
            with open(seerr_settings, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=1)
            logger.info("  [SAVED] Seerr settings overwritten to match code.")
    except Exception as e:
        logger.warning(f"Could not check Seerr settings: {e}")

    return drifts

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

def reconcile_download_client(service_name: str, base_url: str, api_key: str, category_name: str, qb_user: str, qb_pass: str, allow_overwrite: bool = False) -> list[str]:
    """Ensures qBittorrent download client is configured strictly according to declared state."""
    drifts = []
    url = f"{base_url}/api/v3/downloadclient?apikey={api_key}"
    try:
        clients = api_request(url)
        existing = next((c for c in clients if "qbittorrent" in c.get("implementation", "").lower()), None)

        category_field = "tvCategory" if "sonarr" in service_name.lower() else "movieCategory"
        expected_fields = [
            {"name": "host", "value": "qbittorrent"},
            {"name": "port", "value": 8085},
            {"name": "useSsl", "value": False},
            {"name": "username", "value": qb_user},
            {"name": "password", "value": qb_pass},
            {"name": category_field, "value": category_name}
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
            field_diffs = []
            for exp in expected_fields:
                curr_val = current_fields.get(exp["name"])
                if curr_val != exp["value"]:
                    val_show = "***" if "password" in exp["name"].lower() else exp["value"]
                    curr_show = "***" if "password" in exp["name"].lower() else curr_val
                    field_diffs.append(f"{exp['name']}: live='{curr_show}', code='{val_show}'")

            if field_diffs:
                diff_msg = f"{service_name} qBittorrent client drift: {', '.join(field_diffs)}"
                logger.warning(f"  [DRIFT DETECTED] {diff_msg}")
                if not allow_overwrite:
                    drifts.append(diff_msg)
                else:
                    existing["fields"] = expected_fields
                    api_request(f"{base_url}/api/v3/downloadclient/{existing['id']}?apikey={api_key}", method="PUT", data=existing)
                    logger.info(f"  [OVERWRITTEN] Updated qBittorrent download client in {service_name}.")
            else:
                logger.info(f"  [IN_SYNC] qBittorrent download client in {service_name} matches code.")
    except Exception as e:
        logger.warning(f"  [WARN] Could not check download client in {service_name}: {e}")

    return drifts

def normalize_url(u: str) -> str:
    """Normalizes HTTP URLs by removing default port and trailing slashes."""
    if not u:
        return ""
    u = u.rstrip("/")
    if u.endswith(":80"):
        u = u[:-3]
    return u

def reconcile_prowlarr_apps(prowlarr_key: str, sonarr_key: str, radarr_key: str, allow_overwrite: bool = False) -> list[str]:
    """Ensures Prowlarr application sync is in sync with declared services."""
    drifts = []
    url = f"http://prowlarr:80/api/v1/applications?apikey={prowlarr_key}"
    try:
        apps = api_request(url)
        app_map = {a.get("name", "").lower(): a for a in apps}

        targets = [
            ("Sonarr", "http://sonarr", sonarr_key, "SonarrSettings"),
            ("Radarr", "http://radarr", radarr_key, "RadarrSettings"),
        ]

        for name, svc_url, key, contract in targets:
            if not key:
                continue
            existing = app_map.get(name.lower())
            expected_fields = [
                {"name": "prowlarrUrl", "value": "http://prowlarr"},
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
                field_diffs = []
                if curr_fields.get("apiKey") != key:
                    field_diffs.append("apiKey differs")
                if normalize_url(curr_fields.get("baseUrl")) != normalize_url(svc_url):
                    field_diffs.append(f"baseUrl: live='{curr_fields.get('baseUrl')}', code='{svc_url}'")
                if normalize_url(curr_fields.get("prowlarrUrl")) != normalize_url("http://prowlarr"):
                    field_diffs.append(f"prowlarrUrl: live='{curr_fields.get('prowlarrUrl')}', code='http://prowlarr'")

                if field_diffs:
                    diff_msg = f"Prowlarr application '{name}' drift: {', '.join(field_diffs)}"
                    logger.warning(f"  [DRIFT DETECTED] {diff_msg}")
                    if not allow_overwrite:
                        drifts.append(diff_msg)
                    else:
                        existing["fields"] = expected_fields
                        api_request(f"{url}/{existing['id']}?apikey={prowlarr_key}", method="PUT", data=existing)
                        logger.info(f"  [OVERWRITTEN] Updated {name} in Prowlarr.")
                else:
                    logger.info(f"  [IN_SYNC] {name} integration in Prowlarr matches code.")

    except Exception as e:
        logger.warning(f"  [WARN] Could not check Prowlarr applications: {e}")

    return drifts

def auto_wire_services(allow_overwrite: bool = False) -> list[str]:
    """Performs REST API reconciliation."""
    drifts = []
    logger.info("== Phase 2: Checking & Reconciling service integrations via REST APIs ==")

    sonarr_key = os.environ.get("SONARR_API_KEY", "")
    radarr_key = os.environ.get("RADARR_API_KEY", "")
    prowlarr_key = os.environ.get("PROWLARR_API_KEY", "")
    qb_user = os.environ.get("QBITTORRENT_USER", "admin")
    qb_pass = os.environ.get("QBITTORRENT_PASSWORD", "")

    # Reconcile Sonarr download client
    if sonarr_key and wait_for_api("http://sonarr:80/api/v3/system/status?apikey=" + sonarr_key, 10):
        drifts.extend(reconcile_download_client("Sonarr", "http://sonarr:80", sonarr_key, "tv-sonarr", qb_user, qb_pass, allow_overwrite))

    # Reconcile Radarr download client
    if radarr_key and wait_for_api("http://radarr:80/api/v3/system/status?apikey=" + radarr_key, 10):
        drifts.extend(reconcile_download_client("Radarr", "http://radarr:80", radarr_key, "radarr", qb_user, qb_pass, allow_overwrite))

    # Reconcile Prowlarr applications
    if prowlarr_key and wait_for_api("http://prowlarr:80/api/v1/system/status?apikey=" + prowlarr_key, 10):
        drifts.extend(reconcile_prowlarr_apps(prowlarr_key, sonarr_key, radarr_key, allow_overwrite))

    return drifts

def main():
    parser = argparse.ArgumentParser(description="arr-configurator: Media Stack Infrastructure as Code & Drift Reconciliation")
    parser.add_argument("--template-dir", default="/templates", help="Path to config templates")
    parser.add_argument("--config-dir", default="/config", help="Path to /config mount")
    parser.add_argument("--phase", choices=["init", "wire", "all"], default="all", help="Execution phase")
    parser.add_argument("--overwrite-drift", action="store_true", help="Force overwrite running configurations with Git code")
    args = parser.parse_args()

    env_overwrite = os.environ.get("OVERWRITE_DRIFT", "").lower() in ("true", "1", "yes")
    allow_overwrite = args.overwrite_drift or env_overwrite

    if allow_overwrite:
        logger.warning("Mode: OVERWRITE DRIFT ENABLED. Running infrastructure will be forced to match code.")
    else:
        logger.info("Mode: STRICT RECONCILIATION. Any configuration drift will raise an error.")

    all_drifts = []

    if args.phase in ("init", "all"):
        all_drifts.extend(reconcile_templates(args.template_dir, args.config_dir, allow_overwrite=allow_overwrite))
        all_drifts.extend(reconcile_seerr_config(args.config_dir, allow_overwrite=allow_overwrite))

    if args.phase in ("wire", "all"):
        all_drifts.extend(auto_wire_services(allow_overwrite=allow_overwrite))

    if all_drifts:
        drift_report = "\n".join(f"  - {d}" for d in all_drifts)
        msg = (
            f"\n\n{'='*70}\n"
            f"DRIFT DETECTED! Found {len(all_drifts)} difference(s) between code and live environment:\n"
            f"{drift_report}\n\n"
            f"ACTION REQUIRED:\n"
            f"1. To accept running changes: update the templates in Git to match the environment.\n"
            f"2. To overwrite running changes with Git: run with --overwrite-drift or set OVERWRITE_DRIFT=true in .env.\n"
            f"{'='*70}\n"
        )
        logger.error(msg)
        raise DriftDetectedError(f"Configuration drift detected ({len(all_drifts)} items). See logs above for details.")

    logger.info("Reconciliation completed successfully! Infrastructure strictly matches code.")

if __name__ == "__main__":
    main()
