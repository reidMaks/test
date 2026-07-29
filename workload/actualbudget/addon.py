import json
import os
import urllib.request
import urllib.error
import time
import sys
from datetime import datetime, timezone
import logging
from mitmproxy import http
from mitmproxy import ctx

log_level_str = os.environ.get("LOG_LEVEL", "INFO").upper()
log_level = getattr(logging, log_level_str, logging.INFO)
logging.basicConfig(level=log_level, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

class MonobankInjector:
    def __init__(self):
        # We no longer rely on the environment variable globally.
        # We cache client_info per token (for 60s) to prevent Monobank 429 limits during setup.
        self.client_info_cache = {} # Dict[token, {"info": dict, "time": float}]

    def get_client_info(self, token):
        logger.info(f"get_client_info called with token: '{token}'")
        if not token:
            logger.warning("No token provided!")
            return None

        cached = self.client_info_cache.get(token)
        if cached and time.time() - cached["time"] < 60:
            return cached["info"]

        # Prevent concurrent requests from stampeding Monobank API
        if cached:
            self.client_info_cache[token]["time"] = time.time()
        else:
            self.client_info_cache[token] = {"info": None, "time": time.time()}

        req = urllib.request.Request("https://api.monobank.ua/personal/client-info")
        req.add_header("X-Token", token)
        try:
            with urllib.request.urlopen(req) as response:
                info = json.loads(response.read().decode())
                self.client_info_cache[token]["info"] = info
                return info
        except urllib.error.URLError as e:
            logger.error(f"Error fetching client info: {e}")
            if hasattr(e, 'read'):
                logger.error(f"Response: {e.read().decode()}")
            # If we failed but have stale data, return it to prevent 404s
            if cached and cached["info"]:
                return cached["info"]
            return None

    def get_token_from_flow(self, flow: http.HTTPFlow):
        auth_header = flow.request.headers.get("Authorization", "")
        token = ""
        if auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1].strip()

        return token

    def request(self, flow: http.HTTPFlow):
        path = flow.request.path.split("?")[0]
        method = flow.request.method

        if "/api/v2/token/" in path:
            # Here we intercept GoCardless token generation.
            # Actual Budget sends the Secret Key the user typed in the UI.
            try:
                req_data = json.loads(flow.request.content)
                logger.info(f"Token endpoint payload: {req_data}")

                # Check both secret_key and secret_id just in case the user pasted it in the wrong field
                user_token = req_data.get("secret_key", "")
                if not user_token or user_token == "fake-access-token" or len(user_token) < 10:
                    user_token = req_data.get("secret_id", "fake-access-token")

                user_token = user_token.strip()
                logger.info(f"Extracted user token: {user_token}")
            except Exception as e:
                logger.error(f"Error parsing token payload: {e}")
                user_token = "fake-access-token"

            fake_token = {
                "access": user_token,
                "access_expires": 864000000, # Valid for 10,000 days
                "refresh": user_token,
                "refresh_expires": 864000000
            }
            flow.response = http.Response.make(200, json.dumps(fake_token), {"Content-Type": "application/json"})
            return

        if "/api/v2/institutions/" in path:
            if "MONOBANK_UA" in path:
                fake_inst = {
                    "id": "MONOBANK_UA",
                    "name": "Monobank",
                    "bic": "MONOUA",
                    "transaction_total_days": "90",
                    "countries": ["UA"],
                    "logo": ""
                }
                flow.response = http.Response.make(200, json.dumps(fake_inst), {"Content-Type": "application/json"})
                return
            else:
                fake_bank = {
                    "id": "MONOBANK_UA",
                    "name": "Monobank",
                    "bic": "MONOUA",
                    "transaction_total_days": "31",
                    "countries": ["GB", "IE", "FR", "ES", "DE", "IT", "NL", "UA"],
                    "logo": "https://www.monobank.ua/assets/img/logo.svg"
                }
                flow.response = http.Response.make(200, json.dumps([fake_bank]), {"Content-Type": "application/json"})
                return

        if "/api/v2/agreements/" in path:
            fake_agreement = {
                "id": "fake-agreement-123",
                "created": "2026-06-30T00:00:00Z",
                "max_historical_days": 90,
                "access_valid_for_days": 90,
                "access_scope": ["balances", "details", "transactions"],
                "accepted": "2026-06-30T00:00:00Z",
                "institution_id": "MONOBANK_UA"
            }
            flow.response = http.Response.make(200, json.dumps(fake_agreement), {"Content-Type": "application/json"})
            return

        if "/api/v2/requisitions/" in path and method == "POST":
            try:
                req_data = json.loads(flow.request.content)
            except:
                req_data = {}

            fake_req = {
                "id": "fake-req-123",
                "created": "2026-06-30T00:00:00Z",
                "redirect": req_data.get("redirect", "https://actual-test.kms-lab.in.ua/"),
                "status": "LN",
                "institution_id": req_data.get("institution_id", "MONOBANK_UA"),
                "agreement": req_data.get("agreement", "fake-agreement-123"),
                "reference": req_data.get("reference", "fake-ref-123"),
                "accounts": ["mono-account-1"],
                "link": req_data.get("redirect", "https://actual-test.kms-lab.in.ua/")
            }
            flow.response = http.Response.make(200, json.dumps(fake_req), {"Content-Type": "application/json"})
            return

        if "/api/v2/requisitions/" in path and method == "GET":
            token = self.get_token_from_flow(flow)
            ci = self.get_client_info(token)
            accs = []
            if ci:
                for a in ci.get("accounts", []):
                    accs.append(a.get("id"))
                for j in ci.get("jars", []):
                    accs.append(j.get("id"))

            fake_req = {
                "id": "fake-req-123",
                "created": "2026-06-30T00:00:00Z",
                "redirect": "https://actual-test.kms-lab.in.ua/",
                "status": "LN",
                "institution_id": "MONOBANK_UA",
                "agreement": "fake-agreement-123",
                "reference": "fake-ref-123",
                "accounts": accs,
                "link": "https://actual-test.kms-lab.in.ua/"
            }
            flow.response = http.Response.make(200, json.dumps(fake_req), {"Content-Type": "application/json"})
            return

        if "/api/v2/accounts/" in path and method == "GET":
            try:
                parts = path.strip("/").split("/")
                if len(parts) < 4:
                    return

                acc_id = parts[3]
                subpath = parts[4] if len(parts) > 4 else None

                token = self.get_token_from_flow(flow)
                ci = self.get_client_info(token)
                acc_info = None

                logger.debug(f"Looking for acc_id: '{acc_id}' in subpath '{subpath}'")
                if ci:
                    logger.debug(f"ci has {len(ci.get('accounts', []))} accounts and {len(ci.get('jars', []))} jars")
                    for a in ci.get("accounts", []) + ci.get("jars", []):
                        if str(a.get("id")) == str(acc_id):
                            acc_info = a
                            logger.debug("Found acc_info!")
                            break
                else:
                    logger.debug("ci is None!")

                if not acc_info:
                    logger.debug(f"Could not find account {acc_id}")
                    flow.response = http.Response.make(404, "Not Found")
                    return

                if subpath == "balances":
                    bal = acc_info.get("balance", 0) / 100.0
                    res = {
                        "balances": [{
                            "balanceAmount": {"amount": str(bal), "currency": "UAH"},
                            "balanceType": "interimAvailable"
                        }]
                    }
                    flow.response = http.Response.make(200, json.dumps(res), {"Content-Type": "application/json"})
                    return

                elif subpath == "transactions":
                    query = flow.request.query
                    date_from = query.get("date_from")
                    if date_from:
                        try:
                            dt = datetime.strptime(date_from, "%Y-%m-%d").replace(tzinfo=timezone.utc)
                            from_unix = int(dt.timestamp())
                        except:
                            from_unix = int(time.time()) - 30 * 24 * 3600
                    else:
                        from_unix = int(time.time()) - 30 * 24 * 3600

                    now = int(time.time())
                    if now - from_unix > 30 * 24 * 3600:
                        from_unix = now - 30 * 24 * 3600

                    endpoint = f"https://api.monobank.ua/personal/statement/{acc_id}/{from_unix}"
                    req = urllib.request.Request(endpoint)
                    token = self.get_token_from_flow(flow)
                    req.add_header("X-Token", token)

                    try:
                        with urllib.request.urlopen(req) as response:
                            txs = json.loads(response.read().decode())
                    except urllib.error.URLError as e:
                        logger.error(f"Error fetching txs: {e}")
                        if hasattr(e, 'read'):
                            logger.error(f"Response: {e.read().decode()}")
                        txs = []

                    booked = []
                    for t in txs:
                        amt = t.get("amount", 0) / 100.0
                        dt_str = datetime.fromtimestamp(t.get("time", 0), tz=timezone.utc).strftime("%Y-%m-%d")
                        tx_obj = {
                            "transactionId": str(t.get("id", "")),
                            "bookingDate": dt_str,
                            "valueDate": dt_str,
                            "transactionAmount": {
                                "amount": str(amt),
                                "currency": "UAH"
                            },
                            "remittanceInformationUnstructured": t.get("description", ""),
                            "remittanceInformationStructured": t.get("comment", "")
                        }
                        booked.append(tx_obj)

                    res = {"transactions": {"booked": booked, "pending": []}}
                    flow.response = http.Response.make(200, json.dumps(res), {"Content-Type": "application/json"})
                    return

                elif subpath == "details":
                    is_jar = "title" in acc_info
                    if is_jar:
                        name = f"Jar: {acc_info.get('title', '')}"
                    else:
                        masked = acc_info.get('maskedPan', [])
                        pan = masked[0] if (masked and len(masked) > 0) else ""
                        name = f"{acc_info.get('type', 'Account').capitalize()} {pan}"

                    res = {
                        "account": {
                            "id": acc_id,
                            "resourceId": acc_id,
                            "iban": acc_info.get("iban", acc_id),
                            "currency": "UAH",
                            "ownerName": "Monobank Client",
                            "name": name.strip(),
                            "product": "Monobank",
                            "institution_id": "MONOBANK_UA"
                        }
                    }
                    flow.response = http.Response.make(200, json.dumps(res), {"Content-Type": "application/json"})
                    return

                elif not subpath:
                    is_jar = "title" in acc_info
                    if is_jar:
                        name = f"Jar: {acc_info.get('title', '')}"
                    else:
                        masked = acc_info.get('maskedPan', [])
                        pan = masked[0] if (masked and len(masked) > 0) else ""
                        name = f"{acc_info.get('type', 'Account').capitalize()} {pan}"

                    res = {
                        "id": acc_id,
                        "name": name.strip(),
                        "iban": acc_info.get("iban", acc_id),
                        "currency": "UAH",
                        "ownerName": "Monobank Client",
                        "product": "Monobank",
                        "institution_id": "MONOBANK_UA",
                        "status": "READY"
                    }
                    flow.response = http.Response.make(200, json.dumps(res), {"Content-Type": "application/json"})
                    return
            except Exception as e:
                logger.error(f"EXCEPTION: {e}", exc_info=True)
                flow.response = http.Response.make(500, str(e))
                return

        if "/api/v2/" in path:
            logger.info(f"UNMOCKED API REQUEST: {method} {path}")
            flow.response = http.Response.make(200, "{}", {"Content-Type": "application/json"})

addons = [MonobankInjector()]
