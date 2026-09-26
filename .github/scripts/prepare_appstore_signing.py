#!/usr/bin/env python3
"""Create an Apple Distribution certificate and App Store profiles, then write ExportOptions.

Xcode cloud signing is a separate permission from reading /v1/certificates. Run 39
listed certificates and profiles (HTTP 200) and still failed export with
"Cloud signing permission error" and "No signing certificate iOS Distribution".
This script creates a normal distribution certificate (the private key stays on
the runner), installs App Store profiles for the app, widget, and share
extension, and writes a manual ExportOptions.plist. Export must not pass
-allowProvisioningUpdates.
"""

import base64
import json
import os
import plistlib
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_ROOT = "https://api.appstoreconnect.apple.com"
TEAM_ID = "2UMNXHG36N"
APP_GROUP = "group.com.jonathanbowe.jlphysical"
ICLOUD_CONTAINER = "iCloud.com.jonathanbowe.jlphysical"
ASSOCIATED_DOMAIN = "applinks:jl-physical.app"
PROFILE_PREFIX = "JL Physical CI "

TARGETS = (
    {
        "bundle_id": "com.jonathanbowe.jlphysical",
        "profile_name": PROFILE_PREFIX + "App Store",
        "kind": "app",
    },
    {
        "bundle_id": "com.jonathanbowe.jlphysical.FudAIWidgetsExtension",
        "profile_name": PROFILE_PREFIX + "Widgets App Store",
        "kind": "extension",
    },
    {
        "bundle_id": "com.jonathanbowe.jlphysical.calorietrackerShare",
        "profile_name": PROFILE_PREFIX + "Share App Store",
        "kind": "extension",
    },
)


def fail(message):
    print(f"ERROR: {message}")
    raise SystemExit(1)


def api(token, method, url, body=None):
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=payload, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Accept", "application/json")
    if payload is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        raw = error.read()
    text = raw.decode("utf-8", "replace")
    if not text.strip():
        return status, None
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = {"raw": text[:2000]}
    return status, parsed


def error_text(payload):
    if not isinstance(payload, dict):
        return str(payload)
    errors = payload.get("errors")
    if not isinstance(errors, list):
        return json.dumps(payload)[:2000]
    parts = []
    for item in errors:
        if not isinstance(item, dict):
            continue
        parts.append(
            "code={code} status={status} title={title} detail={detail}".format(
                code=item.get("code") or "",
                status=item.get("status") or "",
                title=item.get("title") or "",
                detail=item.get("detail") or "",
            )
        )
    return "; ".join(parts) if parts else json.dumps(payload)[:2000]


def require_ok(status, payload, allowed, what):
    if status not in allowed:
        fail(f"{what} failed HTTP {status}: {error_text(payload)}")
    return payload


def run(args, secret_values=()):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        for secret in secret_values:
            if secret:
                detail = detail.replace(secret, "[redacted]")
        fail(f"{args[0]} {args[1] if len(args) > 1 else ''} failed: {detail}")
    return result


def sign_token():
    import jwt

    key_id = os.environ["KEY_ID"]
    issuer_id = os.environ["ISSUER_ID"]
    key_path = Path.home() / "private_keys" / f"AuthKey_{key_id}.p8"
    if not key_path.is_file():
        fail(f"API key file is missing at {key_path}")
    private_key = key_path.read_text()
    now = int(time.time())
    token = jwt.encode(
        {
            "iss": issuer_id,
            "iat": now,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
    if isinstance(token, bytes):
        token = token.decode()
    print("Signed ES256 JWT for provisioning (token not printed).")
    return token


def find_bundle_resource_id(token, identifier):
    query = "limit=20&filter[identifier]=" + urllib.parse.quote(identifier, safe="")
    status, payload = api(token, "GET", f"{API_ROOT}/v1/bundleIds?{query}")
    require_ok(status, payload, (200,), f"GET bundleIds {identifier}")
    matches = []
    for item in payload.get("data") or []:
        attributes = item.get("attributes") or {}
        if attributes.get("identifier") == identifier:
            matches.append(item)
    if len(matches) != 1:
        found = [
            (item.get("attributes") or {}).get("identifier")
            for item in (payload.get("data") or [])
        ]
        fail(
            f"Expected one bundle ID resource for {identifier}, found {len(matches)}. "
            f"Filter returned {found}."
        )
    print(f"bundle id {identifier} resource={matches[0]['id']}")
    return matches[0]["id"]


def list_capabilities(token, bundle_resource_id):
    status, payload = api(
        token,
        "GET",
        f"{API_ROOT}/v1/bundleIds/{bundle_resource_id}/bundleIdCapabilities?limit=50",
    )
    require_ok(status, payload, (200,), f"GET capabilities for {bundle_resource_id}")
    return payload.get("data") or []


def capability_settings(capability):
    attributes = capability.get("attributes") or {}
    settings = attributes.get("settings")
    return settings if isinstance(settings, list) else []


def post_capability(token, bundle_resource_id, capability_type, settings):
    attributes = {"capabilityType": capability_type}
    if settings is not None:
        attributes["settings"] = settings
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": attributes,
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bundle_resource_id}
                }
            },
        }
    }
    return api(token, "POST", f"{API_ROOT}/v1/bundleIdCapabilities", body)


def ensure_capability(token, bundle_resource_id, capability_type, settings_attempts, needle):
    existing = list_capabilities(token, bundle_resource_id)
    current = None
    for capability in existing:
        attributes = capability.get("attributes") or {}
        if attributes.get("capabilityType") == capability_type:
            current = capability
            break
    if current is not None:
        blob = json.dumps(capability_settings(current))
        if needle is None or needle in blob:
            print(f"capability {capability_type} already enabled on {bundle_resource_id}")
            return
        print(f"capability {capability_type} is enabled without {needle}; updating it")
        updated = list(capability_settings(current))
        if settings_attempts and settings_attempts[0]:
            updated = settings_attempts[0]
        status, payload = api(
            token,
            "PATCH",
            f"{API_ROOT}/v1/bundleIdCapabilities/{current['id']}",
            {
                "data": {
                    "type": "bundleIdCapabilities",
                    "id": current["id"],
                    "attributes": {
                        "capabilityType": capability_type,
                        "settings": updated,
                    },
                }
            },
        )
        if status in (200, 201):
            print(f"updated {capability_type}")
            return
        print(f"WARNING: could not update {capability_type} HTTP {status}: {error_text(payload)}")
        return

    errors = []
    for settings in settings_attempts:
        status, payload = post_capability(token, bundle_resource_id, capability_type, settings)
        if status in (200, 201):
            print(f"enabled {capability_type} on {bundle_resource_id}")
            return
        if status == 409:
            print(f"capability {capability_type} already exists (409)")
            return
        errors.append(f"HTTP {status}: {error_text(payload)}")
        if status == 403:
            break
    fail(
        f"Could not enable {capability_type} on {bundle_resource_id}. "
        + " | ".join(errors)
    )


def enable_target_capabilities(token, bundle_resource_id, kind):
    group_settings = (
        [
            {
                "key": "APP_GROUP_IDS",
                "options": [{"key": APP_GROUP, "enabled": True}],
            }
        ],
        [
            {
                "key": "APP_GROUPS",
                "options": [{"key": APP_GROUP, "enabled": True}],
            }
        ],
    )
    ensure_capability(token, bundle_resource_id, "APP_GROUPS", group_settings, APP_GROUP)
    if kind != "app":
        return
    ensure_capability(
        token,
        bundle_resource_id,
        "ASSOCIATED_DOMAINS",
        (
            [
                {
                    "key": "ASSOCIATED_DOMAIN_IDS",
                    "options": [{"key": ASSOCIATED_DOMAIN, "enabled": True}],
                }
            ],
            None,
        ),
        None,
    )
    ensure_capability(
        token,
        bundle_resource_id,
        "ICLOUD",
        (
            [
                {
                    "key": "ICLOUD_VERSION",
                    "options": [{"key": "XCODE_13", "enabled": True}],
                }
            ],
            [
                {
                    "key": "ICLOUD_VERSION",
                    "options": [{"key": "XCODE_6", "enabled": True}],
                }
            ],
        ),
        None,
    )
    ensure_capability(token, bundle_resource_id, "HEALTHKIT", (None,), None)
    status, payload = api(
        token,
        "GET",
        f"{API_ROOT}/v1/capabilities?limit=200&filter[bundleId]={bundle_resource_id}",
    )
    if status != 200 or not isinstance(payload, dict):
        print(f"WARNING: could not list capability templates HTTP {status}")
        return
    for item in payload.get("data") or []:
        cap_id = str(item.get("id") or "")
        name = str((item.get("attributes") or {}).get("name") or "")
        label = f"{cap_id} {name}".upper()
        if "HEALTH" in label and "BACKGROUND" in label and cap_id:
            print(f"enabling health background capability {cap_id}")
            ensure_capability(token, bundle_resource_id, cap_id, (None,), None)


def list_certificates(token):
    status, payload = api(token, "GET", f"{API_ROOT}/v1/certificates?limit=200")
    require_ok(status, payload, (200,), "GET certificates")
    return payload.get("data") or []


def is_certificate_limit(status, payload):
    if status not in (400, 409, 422):
        return False
    text = error_text(payload).lower()
    return any(
        phrase in text
        for phrase in ("maximum", "limit", "already have", "too many")
    )


def delete_certificate(token, certificate):
    certificate_id = certificate["id"]
    attributes = certificate.get("attributes") or {}
    print(
        "Deleting Apple Distribution certificate "
        f"{certificate_id} type={attributes.get('certificateType')} "
        f"expires={attributes.get('expirationDate')} so a new one can be created. "
        "IOS_DISTRIBUTION and DEVELOPMENT certificates are left in place."
    )
    status, payload = api(token, "DELETE", f"{API_ROOT}/v1/certificates/{certificate_id}")
    require_ok(status, payload, (204, 200), f"DELETE certificate {certificate_id}")


def create_distribution_certificate(token, csr_pem):
    certificates = list_certificates(token)
    counts = {}
    for certificate in certificates:
        certificate_type = (certificate.get("attributes") or {}).get("certificateType") or "unknown"
        counts[certificate_type] = counts.get(certificate_type, 0) + 1
    print(f"existing certificates: {counts}")

    def distribution_certs():
        current = list_certificates(token)
        return [
            certificate
            for certificate in current
            if (certificate.get("attributes") or {}).get("certificateType") == "DISTRIBUTION"
        ]

    for attempt in range(2):
        status, payload = api(
            token,
            "POST",
            f"{API_ROOT}/v1/certificates",
            {
                "data": {
                    "type": "certificates",
                    "attributes": {
                        "certificateType": "DISTRIBUTION",
                        "csrContent": csr_pem,
                    },
                }
            },
        )
        if status in (200, 201):
            attributes = (payload.get("data") or {}).get("attributes") or {}
            print(
                "created DISTRIBUTION certificate "
                f"id={(payload.get('data') or {}).get('id')} "
                f"name={attributes.get('name')} expires={attributes.get('expirationDate')}"
            )
            return payload["data"], "Apple Distribution"
        if status == 403:
            fail(
                "Apple refused to create a distribution certificate (403). "
                "Run 39 could read certificates, and Xcode cloud signing was also denied "
                "('You haven't been given access to cloud-managed distribution certificates'). "
                "The key needs Admin or Account Holder, Access to Certificates, Identifiers & Profiles, "
                "and permission to create certificates. "
                f"Apple said: {error_text(payload)}"
            )
        if is_certificate_limit(status, payload) and attempt == 0:
            existing = distribution_certs()
            if not existing:
                fail(
                    "Apple refused another distribution certificate and none of type "
                    f"DISTRIBUTION can be removed. Apple said: {error_text(payload)}"
                )
            oldest = sorted(
                existing,
                key=lambda certificate: (certificate.get("attributes") or {}).get("expirationDate")
                or "",
            )[0]
            delete_certificate(token, oldest)
            continue
        fail(f"POST certificate failed HTTP {status}: {error_text(payload)}")
    fail("Could not create a distribution certificate.")


def generate_key_and_csr(work_dir):
    key_path = work_dir / "distribution.key"
    csr_path = work_dir / "distribution.csr"
    run(["openssl", "genrsa", "-out", str(key_path), "2048"])
    key_path.chmod(0o600)
    run(
        [
            "openssl",
            "req",
            "-new",
            "-key",
            str(key_path),
            "-out",
            str(csr_path),
            "-subj",
            "/CN=JL Physical CI/O=JL Physical/C=US",
        ]
    )
    return key_path, csr_path.read_text()


def import_certificate(work_dir, certificate, key_path):
    attributes = certificate.get("attributes") or {}
    encoded = attributes.get("certificateContent")
    if not encoded:
        fail("Certificate response did not include certificateContent.")
    cert_der = work_dir / "distribution.cer"
    cert_pem = work_dir / "distribution.pem"
    p12_path = work_dir / "distribution.p12"
    cert_der.write_bytes(base64.b64decode(encoded))
    run(
        ["openssl", "x509", "-inform", "DER", "-in", str(cert_der), "-out", str(cert_pem)]
    )
    password = secrets.token_urlsafe(24)
    export = subprocess.run(
        [
            "openssl",
            "pkcs12",
            "-export",
            "-inkey",
            str(key_path),
            "-in",
            str(cert_pem),
            "-out",
            str(p12_path),
            "-passout",
            f"pass:{password}",
            "-name",
            "Apple Distribution",
        ],
        capture_output=True,
        text=True,
    )
    if export.returncode != 0:
        export = subprocess.run(
            [
                "openssl",
                "pkcs12",
                "-legacy",
                "-export",
                "-inkey",
                str(key_path),
                "-in",
                str(cert_pem),
                "-out",
                str(p12_path),
                "-passout",
                f"pass:{password}",
                "-name",
                "Apple Distribution",
            ],
            capture_output=True,
            text=True,
        )
    if export.returncode != 0:
        fail(f"Could not export the distribution certificate to a p12. {export.stderr.strip()}")

    keychain = work_dir / "jl-appstore.keychain-db"
    run(
        ["security", "create-keychain", "-p", password, str(keychain)],
        secret_values=(password,),
    )
    run(
        ["security", "set-keychain-settings", "-lut", "21600", str(keychain)],
        secret_values=(password,),
    )
    run(
        ["security", "unlock-keychain", "-p", password, str(keychain)],
        secret_values=(password,),
    )
    existing = subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True)
    search_list = [str(keychain)]
    for line in existing.splitlines():
        cleaned = line.strip().strip('"')
        if cleaned and cleaned not in search_list:
            search_list.append(cleaned)
    run(["security", "list-keychains", "-d", "user", "-s", *search_list])
    run(["security", "default-keychain", "-s", str(keychain)])
    run(
        [
            "security",
            "import",
            str(p12_path),
            "-k",
            str(keychain),
            "-P",
            password,
            "-T",
            "/usr/bin/codesign",
            "-T",
            "/usr/bin/security",
        ],
        secret_values=(password,),
    )
    run(
        [
            "security",
            "set-key-partition-list",
            "-S",
            "apple-tool:,apple:,codesign:",
            "-s",
            "-k",
            password,
            str(keychain),
        ],
        secret_values=(password,),
    )
    identities = subprocess.check_output(
        ["security", "find-identity", "-v", "-p", "codesigning", str(keychain)],
        text=True,
    )
    print(identities.strip())
    if "Distribution" not in identities:
        fail("The new certificate is not a valid code signing identity in the keychain.")
    path_file = work_dir / "jl-keychain-path"
    path_file.write_text(str(keychain))
    key_path.unlink(missing_ok=True)
    p12_path.unlink(missing_ok=True)
    return path_file


def list_profiles(token):
    status, payload = api(token, "GET", f"{API_ROOT}/v1/profiles?limit=200")
    require_ok(status, payload, (200,), "GET profiles")
    return payload.get("data") or []


def delete_profile(token, profile):
    profile_id = profile["id"]
    name = (profile.get("attributes") or {}).get("name")
    print(f"Deleting previous CI profile {name} ({profile_id})")
    status, payload = api(token, "DELETE", f"{API_ROOT}/v1/profiles/{profile_id}")
    require_ok(status, payload, (204, 200), f"DELETE profile {profile_id}")


def create_profile(token, name, bundle_resource_id, certificate_id):
    body = {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                "certificates": {
                    "data": [{"type": "certificates", "id": certificate_id}]
                },
                "devices": {"data": []},
            },
        }
    }
    status, payload = api(token, "POST", f"{API_ROOT}/v1/profiles", body)
    if status == 409:
        for profile in list_profiles(token):
            if (profile.get("attributes") or {}).get("name") == name:
                delete_profile(token, profile)
        status, payload = api(token, "POST", f"{API_ROOT}/v1/profiles", body)
    require_ok(status, payload, (200, 201), f"POST profile {name}")
    return payload["data"]


def install_profile(profile, profiles_dir):
    attributes = profile.get("attributes") or {}
    encoded = attributes.get("profileContent")
    if not encoded:
        fail(f"Profile {attributes.get('name')} did not include profileContent.")
    raw_path = profiles_dir / f"{profile['id']}.mobileprovision"
    raw_path.write_bytes(base64.b64decode(encoded))
    decoded_path = profiles_dir / f"{profile['id']}.plist"
    run(["security", "cms", "-D", "-i", str(raw_path), "-o", str(decoded_path)])
    with decoded_path.open("rb") as decoded_file:
        decoded = plistlib.load(decoded_file)
    uuid = decoded.get("UUID")
    name = decoded.get("Name")
    if not uuid or not name:
        fail(f"Decoded profile {attributes.get('name')} has no UUID or Name.")
    installed = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"
    installed.mkdir(parents=True, exist_ok=True)
    destination = installed / f"{uuid}.mobileprovision"
    destination.write_bytes(raw_path.read_bytes())
    print(f"installed profile name={name} uuid={uuid}")
    return decoded


def values_of(entitlements, key):
    value = entitlements.get(key)
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def is_enabled(value):
    return value is True or value == 1


def profile_problems(entitlements, kind):
    problems = []
    groups = values_of(entitlements, "com.apple.security.application-groups")
    if APP_GROUP not in groups:
        problems.append(
            f"application-groups {groups or 'missing'} does not include {APP_GROUP}"
        )
    if kind != "app":
        return problems
    if not is_enabled(entitlements.get("com.apple.developer.healthkit")):
        problems.append("HealthKit entitlement is missing")
    if not is_enabled(entitlements.get("com.apple.developer.healthkit.background-delivery")):
        problems.append("HealthKit background-delivery entitlement is missing")
    icloud_services = values_of(entitlements, "com.apple.developer.icloud-services")
    if "CloudKit" not in icloud_services:
        problems.append(f"iCloud services {icloud_services or 'missing'} does not include CloudKit")
    containers = values_of(entitlements, "com.apple.developer.icloud-container-identifiers")
    if ICLOUD_CONTAINER not in containers and "*" not in containers and "iCloud.*" not in containers:
        problems.append(
            f"iCloud containers {containers or 'missing'} does not include {ICLOUD_CONTAINER}"
        )
    if "com.apple.developer.associated-domains" not in entitlements:
        problems.append("associated-domains entitlement is missing")
    return problems


def write_export_options(path, profiles_by_bundle_id, signing_certificate):
    plist = {
        "method": "app-store-connect",
        "teamID": TEAM_ID,
        "uploadSymbols": True,
        "signingStyle": "manual",
        "signingCertificate": signing_certificate,
        "destination": "export",
        "manageAppVersionAndBuildNumber": False,
        "provisioningProfiles": profiles_by_bundle_id,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as plist_file:
        plistlib.dump(plist, plist_file)
    print(f"wrote {path}")


def self_check():
    extension_ok = {"com.apple.security.application-groups": [APP_GROUP]}
    if profile_problems(extension_ok, "extension"):
        fail("extension profile with the app group was rejected")
    if not profile_problems({}, "extension"):
        fail("extension profile without the app group was accepted")
    app_ok = {
        "com.apple.security.application-groups": [APP_GROUP],
        "com.apple.developer.healthkit": True,
        "com.apple.developer.healthkit.background-delivery": True,
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-identifiers": [ICLOUD_CONTAINER],
        "com.apple.developer.associated-domains": "*",
    }
    if profile_problems(app_ok, "app"):
        fail("complete app profile was rejected")
    if not profile_problems(
        {"com.apple.security.application-groups": [APP_GROUP]},
        "app",
    ):
        fail("app profile missing HealthKit was accepted")
    print("self-check ok")


def main():
    export_options = Path(os.environ["EXPORT_OPTIONS_PLIST"])
    work_dir = Path(os.environ["RUNNER_TEMP"]) / "jl-appstore-signing"
    work_dir.mkdir(parents=True, exist_ok=True)
    token = sign_token()

    resolved = []
    for target in TARGETS:
        bundle_resource_id = find_bundle_resource_id(token, target["bundle_id"])
        enable_target_capabilities(token, bundle_resource_id, target["kind"])
        resolved.append((target, bundle_resource_id))

    key_path, csr_pem = generate_key_and_csr(work_dir)
    certificate, signing_certificate = create_distribution_certificate(token, csr_pem)
    import_certificate(work_dir, certificate, key_path)

    for profile in list_profiles(token):
        name = (profile.get("attributes") or {}).get("name") or ""
        if name.startswith(PROFILE_PREFIX):
            delete_profile(token, profile)

    profiles_by_bundle_id = {}
    for target, bundle_resource_id in resolved:
        profile = create_profile(
            token,
            target["profile_name"],
            bundle_resource_id,
            certificate["id"],
        )
        decoded = install_profile(profile, work_dir)
        problems = profile_problems(decoded.get("Entitlements") or {}, target["kind"])
        if problems:
            print(
                "Profile entitlements are not ready yet ("
                + "; ".join(problems)
                + "). Recreating the profile once."
            )
            delete_profile(token, profile)
            time.sleep(3)
            profile = create_profile(
                token,
                target["profile_name"],
                bundle_resource_id,
                certificate["id"],
            )
            decoded = install_profile(profile, work_dir)
            problems = profile_problems(decoded.get("Entitlements") or {}, target["kind"])
        if problems:
            rendered = json.dumps(decoded.get("Entitlements") or {}, default=str)[:2000]
            fail(
                f"Profile {target['profile_name']} is missing entitlements: "
                + "; ".join(problems)
                + f". Profile entitlements: {rendered}"
            )
        profiles_by_bundle_id[target["bundle_id"]] = decoded["UUID"]
        print(f"profile {target['profile_name']} matches {target['bundle_id']}")

    write_export_options(export_options, profiles_by_bundle_id, signing_certificate)
    print("App Store signing material is ready for manual export.")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        self_check()
    else:
        main()
