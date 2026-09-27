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
import tempfile
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


def resolve_api_key_id(environ=None):
    """Prefer the Admin API key when both of its secrets are non-empty.

    Returns (key id, label). The label names the secret pair and never includes
    key material. Issuer stays ISSUER_ID either way.
    """
    env = os.environ if environ is None else environ
    admin_key_id = (env.get("ADMIN_KEY_ID") or "").strip()
    admin_auth_key = (env.get("ADMIN_AUTH_KEY") or "").strip()
    fallback_key_id = (env.get("KEY_ID") or "").strip()
    if admin_key_id and admin_auth_key:
        return admin_key_id, "admin (ADMIN_KEY_ID / ADMIN_AUTH_KEY)"
    return fallback_key_id, "default (KEY_ID / AUTH_KEY)"


def sign_token():
    import jwt

    key_id, key_label = resolve_api_key_id()
    print(f"Using App Store Connect API key: {key_label}")
    if not key_id:
        fail(
            "No App Store Connect API key is available. "
            "Set ADMIN_KEY_ID and ADMIN_AUTH_KEY, or KEY_ID and AUTH_KEY."
        )
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


def bundle_id_capabilities_url(bundle_resource_id):
    # This relationship rejects ?limit (PARAMETER_ERROR.ILLEGAL). Do not add it.
    return f"{API_ROOT}/v1/bundleIds/{bundle_resource_id}/bundleIdCapabilities"


def list_capabilities(token, bundle_resource_id):
    collected = []
    url = bundle_id_capabilities_url(bundle_resource_id)
    while url:
        status, payload = api(token, "GET", url)
        require_ok(status, payload, (200,), f"GET capabilities for {bundle_resource_id}")
        collected.extend(payload.get("data") or [])
        links = payload.get("links") if isinstance(payload, dict) else None
        url = links.get("next") if isinstance(links, dict) else None
    return collected


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


# Apple's bundleIdCapabilities schema accepts only these setting and option keys.
# Run 41 rejected APP_GROUP_IDS with HTTP 409 ENTITY_ERROR.ATTRIBUTE.TYPE and
# listed exactly these setting keys. XCODE_13, ASSOCIATED_DOMAIN_IDS, and
# APP_GROUPS-as-a-setting-key are not in the schema. A 409 of that class is a
# rejected payload, not "capability already exists".
ALLOWED_SETTING_KEYS = frozenset(
    {
        "ICLOUD_VERSION",
        "DATA_PROTECTION_PERMISSION_LEVEL",
        "APPLE_ID_AUTH_APP_CONSENT",
    }
)
ALLOWED_OPTION_KEYS = frozenset(
    {
        "XCODE_5",
        "XCODE_6",
        "COMPLETE_PROTECTION",
        "PROTECTED_UNLESS_OPEN",
        "PROTECTED_UNTIL_FIRST_USER_AUTH",
        "PRIMARY_APP_CONSENT",
    }
)

# XCODE_6 enables CloudKit. XCODE_5 is iCloud Documents and does not put
# CloudKit on the profile. The public API has no setting for a container id;
# CloudKit uses the default container iCloud.<bundle id>.
ICLOUD_CLOUDKIT_SETTINGS = [
    {
        "key": "ICLOUD_VERSION",
        "options": [{"key": "XCODE_6", "enabled": True}],
    }
]


def capability_plan(kind):
    """Capabilities to enable. None means capabilityType only, with no settings.

    App group identifiers and associated-domain strings are not capability
    settings. The App Group is already attached to these bundle IDs and is
    checked on the profile. Associated Domains with no settings puts
    com.apple.developer.associated-domains on the profile; the applinks value
    stays in the entitlements file.
    """
    plan = [("APP_GROUPS", None)]
    if kind == "app":
        plan.extend(
            [
                ("ASSOCIATED_DOMAINS", None),
                ("ICLOUD", ICLOUD_CLOUDKIT_SETTINGS),
                ("HEALTHKIT", None),
            ]
        )
    return plan


def assert_settings_allowed(settings):
    if settings is None:
        return
    if not isinstance(settings, list) or not settings:
        fail("capability settings must be a non-empty list or omitted")
    for setting in settings:
        if not isinstance(setting, dict):
            fail("capability setting must be an object")
        key = setting.get("key")
        if key not in ALLOWED_SETTING_KEYS:
            fail(
                f"refusing to send capability setting key {key!r}. "
                f"Apple accepts only {sorted(ALLOWED_SETTING_KEYS)}."
            )
        options = setting.get("options") or []
        if not isinstance(options, list) or not options:
            fail(f"capability setting {key} needs at least one option")
        for option in options:
            if not isinstance(option, dict):
                fail(f"capability option for {key} must be an object")
            option_key = option.get("key")
            if option_key not in ALLOWED_OPTION_KEYS:
                fail(
                    f"refusing to send capability option key {option_key!r}. "
                    f"Apple accepts only {sorted(ALLOWED_OPTION_KEYS)}."
                )


def is_invalid_settings_error(payload):
    text = error_text(payload).lower()
    markers = (
        "not a valid value",
        "expected one of",
        "attribute.type",
        "wrong type",
        "entity_error.attribute.type",
    )
    return any(marker in text for marker in markers)


def is_duplicate_conflict(status, payload):
    if status != 409:
        return False
    return not is_invalid_settings_error(payload)


def find_capability(capabilities, capability_type):
    for capability in capabilities:
        attributes = capability.get("attributes") or {}
        if attributes.get("capabilityType") == capability_type:
            return capability
    return None


def describe_capability(capability):
    attributes = capability.get("attributes") or {}
    pieces = []
    for setting in capability_settings(capability):
        if not isinstance(setting, dict):
            continue
        option_bits = []
        for option in setting.get("options") or []:
            if isinstance(option, dict):
                option_bits.append(f"{option.get('key')}:enabled={option.get('enabled')}")
        pieces.append(f"{setting.get('key')}[{', '.join(option_bits)}]")
    rendered = ", ".join(pieces) if pieces else "no settings"
    print(
        f"existing capability type={attributes.get('capabilityType')} "
        f"id={capability.get('id')} {rendered}"
    )


def icloud_cloudkit_enabled(capability):
    for setting in capability_settings(capability):
        if not isinstance(setting, dict) or setting.get("key") != "ICLOUD_VERSION":
            continue
        for option in setting.get("options") or []:
            if (
                isinstance(option, dict)
                and option.get("key") == "XCODE_6"
                and option.get("enabled") is True
            ):
                return True
    return False


def patch_capability(token, capability, capability_type, settings):
    assert_settings_allowed(settings)
    capability_id = capability["id"]
    status, payload = api(
        token,
        "PATCH",
        f"{API_ROOT}/v1/bundleIdCapabilities/{capability_id}",
        {
            "data": {
                "type": "bundleIdCapabilities",
                "id": capability_id,
                "attributes": {
                    "capabilityType": capability_type,
                    "settings": settings,
                },
            }
        },
    )
    if status not in (200, 201):
        fail(
            f"Could not update {capability_type} {capability_id} "
            f"HTTP {status}: {error_text(payload)}"
        )
    print(f"updated {capability_type} id={capability_id}")


def ensure_capability(token, bundle_resource_id, capability_type, settings):
    assert_settings_allowed(settings)
    existing = list_capabilities(token, bundle_resource_id)
    for capability in existing:
        describe_capability(capability)
    current = find_capability(existing, capability_type)
    if current is None:
        status, payload = post_capability(
            token, bundle_resource_id, capability_type, settings
        )
        if status in (200, 201):
            print(f"enabled {capability_type} on {bundle_resource_id}")
            return
        if not is_duplicate_conflict(status, payload):
            fail(
                f"Could not enable {capability_type} on {bundle_resource_id} "
                f"HTTP {status}: {error_text(payload)}"
            )
        print(
            f"capability {capability_type} reported a duplicate "
            f"HTTP {status}: {error_text(payload)}"
        )
        existing = list_capabilities(token, bundle_resource_id)
        current = find_capability(existing, capability_type)
        if current is None:
            fail(
                f"{capability_type} returned HTTP {status} but is not listed "
                f"on {bundle_resource_id}. Apple said: {error_text(payload)}"
            )
    if capability_type == "ICLOUD" and not icloud_cloudkit_enabled(current):
        print(
            f"capability ICLOUD on {bundle_resource_id} is missing CloudKit "
            "(XCODE_6); updating it"
        )
        patch_capability(token, current, capability_type, ICLOUD_CLOUDKIT_SETTINGS)
        return
    print(f"capability {capability_type} already enabled on {bundle_resource_id}")


def enable_target_capabilities(token, bundle_resource_id, kind):
    for capability_type, settings in capability_plan(kind):
        ensure_capability(token, bundle_resource_id, capability_type, settings)


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


IOS_ROOT = Path(__file__).resolve().parents[2] / "ios"
APP_ENTITLEMENTS_PATH = IOS_ROOT / "calorietracker" / "calorietracker.entitlements"
WIDGET_ENTITLEMENTS_PATH = IOS_ROOT / "FudAIWidgets" / "FudAIWidgets.entitlements"
SHARE_ENTITLEMENTS_PATH = IOS_ROOT / "calorietrackerShare" / "calorietrackerShare.entitlements"
HEALTHKIT_KEY = "com.apple.developer.healthkit"
HEALTHKIT_ACCESS_KEY = "com.apple.developer.healthkit.access"
ICLOUD_SERVICES_KEY = "com.apple.developer.icloud-services"
ICLOUD_CONTAINERS_KEY = "com.apple.developer.icloud-container-identifiers"
ICLOUD_ENVIRONMENT_KEY = "com.apple.developer.icloud-container-environment"
APPLICATION_IDENTIFIER_KEY = "application-identifier"
TEAM_IDENTIFIER_KEY = "com.apple.developer.team-identifier"


def values_of(entitlements, key):
    value = entitlements.get(key)
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def is_enabled(value):
    return value is True or value == 1


def expand_build_settings(value, substitutions):
    if isinstance(value, str):
        expanded = value
        for name, replacement in substitutions.items():
            expanded = expanded.replace(f"$({name})", replacement)
        return expanded
    if isinstance(value, list):
        return [expand_build_settings(item, substitutions) for item in value]
    if isinstance(value, dict):
        return {
            key: expand_build_settings(item, substitutions) for key, item in value.items()
        }
    return value


def app_signing_requirements(bundle_id):
    """Entitlements the App Store profile must cover, with build settings expanded."""
    if not APP_ENTITLEMENTS_PATH.is_file():
        fail(f"App entitlements file is missing at {APP_ENTITLEMENTS_PATH}")
    with APP_ENTITLEMENTS_PATH.open("rb") as entitlements_file:
        raw = plistlib.load(entitlements_file)
    return expand_build_settings(
        raw,
        {
            "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
            "APP_GROUP_IDENTIFIER": APP_GROUP,
        },
    )


def icloud_services_satisfied(profile_services, required_services):
    """Apple distribution profiles use '*' for CloudKit and CloudDocuments."""
    if "*" in profile_services:
        return True
    return all(service in profile_services for service in required_services)


def containers_satisfied(profile_containers, required_containers):
    if not required_containers:
        return True
    if "*" in profile_containers or "iCloud.*" in profile_containers:
        return True
    return all(container in profile_containers for container in required_containers)


def distribution_entitlement_problems(bundle_id):
    """The signed app keeps an explicit CloudKit service list.

    A wildcard profile still accepts com.apple.developer.icloud-services =
    ['CloudKit']. icloud-container-environment is checked only when the app
    sets it; distribution must then be Production.
    """
    required = app_signing_requirements(bundle_id)
    problems = []
    services = values_of(required, ICLOUD_SERVICES_KEY)
    if services != ["CloudKit"]:
        problems.append(
            "app entitlements com.apple.developer.icloud-services must stay "
            f"['CloudKit'] (wildcard profiles still accept that). Found {services or 'missing'}."
        )
    if ICLOUD_ENVIRONMENT_KEY in required:
        environments = values_of(required, ICLOUD_ENVIRONMENT_KEY)
        if environments != ["Production"]:
            problems.append(
                "app entitlements set icloud-container-environment to "
                f"{environments}. Distribution must set it to ['Production']."
            )
    if not is_enabled(required.get("com.apple.developer.healthkit")):
        problems.append("app entitlements com.apple.developer.healthkit must be true")
    access = required.get("com.apple.developer.healthkit.access")
    if not isinstance(access, list):
        problems.append(
            "app entitlements com.apple.developer.healthkit.access must be an array"
        )
    return problems


def profile_problems(entitlements, kind, bundle_id="com.jonathanbowe.jlphysical"):
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
    if not isinstance(entitlements.get("com.apple.developer.healthkit.access"), list):
        problems.append("HealthKit access entitlement is missing")
    required = app_signing_requirements(bundle_id)
    required_services = values_of(required, ICLOUD_SERVICES_KEY)
    profile_services = values_of(entitlements, ICLOUD_SERVICES_KEY)
    if not icloud_services_satisfied(profile_services, required_services):
        problems.append(
            f"iCloud services {profile_services or 'missing'} does not include {required_services}"
        )
    required_containers = values_of(required, ICLOUD_CONTAINERS_KEY)
    profile_containers = values_of(entitlements, ICLOUD_CONTAINERS_KEY)
    if not containers_satisfied(profile_containers, required_containers):
        problems.append(
            "iCloud containers "
            f"{profile_containers or 'missing'} does not include {required_containers}"
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


def load_expanded_entitlements(path, bundle_id):
    if not path.is_file():
        fail(f"Entitlements file is missing at {path}")
    with path.open("rb") as entitlements_file:
        raw = plistlib.load(entitlements_file)
    return expand_build_settings(
        raw,
        {
            "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
            "APP_GROUP_IDENTIFIER": APP_GROUP,
        },
    )


def uses_icloud(entitlements):
    return ICLOUD_SERVICES_KEY in entitlements or ICLOUD_CONTAINERS_KEY in entitlements


def complete_app_store_entitlements(path, bundle_id):
    """Entitlements codesign embeds for an App Store re-sign.

    The source files omit application-identifier. Passing only those keys
    replaces the export signature and drops TeamID.bundleId from the app,
    widget, and share extension. iCloud container identifiers without an
    environment make codesign write an empty icloud-container-environment
    string. App Store validation requires that value to be the string
    Production. The source file stays unchanged so local development is not
    forced to Production.
    """
    entitlements = load_expanded_entitlements(path, bundle_id)
    entitlements[APPLICATION_IDENTIFIER_KEY] = f"{TEAM_ID}.{bundle_id}"
    entitlements[TEAM_IDENTIFIER_KEY] = TEAM_ID
    if uses_icloud(entitlements):
        entitlements[ICLOUD_ENVIRONMENT_KEY] = "Production"
    else:
        entitlements.pop(ICLOUD_ENVIRONMENT_KEY, None)
    return entitlements


def write_archived_entitlements(archive_path):
    """Write archived-expanded-entitlements.xcent into an unsigned archive.

    Archive uses CODE_SIGNING_ALLOWED=NO, so ProcessProductPackaging never
    runs. Xcode 26 export still ignores this file and signs with profile
    defaults, which omit HealthKit. resign_ipa() applies the entitlements
    after export.
    """
    archive = Path(archive_path)
    if not archive.is_dir():
        fail(f"Archive was not found at {archive}")
    bundles = (
        (
            "Products/Applications/calorietracker.app",
            APP_ENTITLEMENTS_PATH,
            "com.jonathanbowe.jlphysical",
        ),
        (
            "Products/Applications/calorietracker.app/PlugIns/FudAIWidgetsExtension.appex",
            WIDGET_ENTITLEMENTS_PATH,
            "com.jonathanbowe.jlphysical.FudAIWidgetsExtension",
        ),
        (
            "Products/Applications/calorietracker.app/PlugIns/calorietrackerShare.appex",
            SHARE_ENTITLEMENTS_PATH,
            "com.jonathanbowe.jlphysical.calorietrackerShare",
        ),
    )
    for relative, entitlements_path, bundle_id in bundles:
        bundle_dir = archive / relative
        if not bundle_dir.is_dir():
            fail(f"Archive is missing {relative}")
        expanded = complete_app_store_entitlements(entitlements_path, bundle_id)
        if bundle_id == "com.jonathanbowe.jlphysical":
            if not is_enabled(expanded.get(HEALTHKIT_KEY)):
                fail("Expanded app entitlements are missing HealthKit")
            if not isinstance(expanded.get(HEALTHKIT_ACCESS_KEY), list):
                fail("Expanded app entitlements are missing HealthKit access")
        destination = bundle_dir / "archived-expanded-entitlements.xcent"
        with destination.open("wb") as entitlements_file:
            plistlib.dump(expanded, entitlements_file)
        print(f"wrote {destination}")


def nested_code_to_preserve(app):
    """Frameworks and dylibs, deepest first, so a parent seal is written later."""
    found = []
    for path in app.rglob("*"):
        if path.suffix == ".framework" and path.is_dir():
            found.append(path)
        elif path.suffix == ".dylib" and path.is_file():
            found.append(path)
    found.sort(key=lambda path: len(path.parts), reverse=True)
    return found


def resign_plan(app):
    """Inside-out sign steps: preserved nested code, then appexes, then the app.

    Each step is (bundle path, entitlements or None). None keeps the nested
    code's existing entitlements. The app step carries HealthKit.
    """
    steps = [(path, None) for path in nested_code_to_preserve(app)]
    bundles = (
        (
            "PlugIns/FudAIWidgetsExtension.appex",
            WIDGET_ENTITLEMENTS_PATH,
            "com.jonathanbowe.jlphysical.FudAIWidgetsExtension",
        ),
        (
            "PlugIns/calorietrackerShare.appex",
            SHARE_ENTITLEMENTS_PATH,
            "com.jonathanbowe.jlphysical.calorietrackerShare",
        ),
        (".", APP_ENTITLEMENTS_PATH, "com.jonathanbowe.jlphysical"),
    )
    for relative, entitlements_path, bundle_id in bundles:
        target = app if relative == "." else app / relative
        steps.append((target, complete_app_store_entitlements(entitlements_path, bundle_id)))
    return steps


def distribution_signing_identity():
    runner_temp = os.environ.get("RUNNER_TEMP")
    if not runner_temp:
        fail("RUNNER_TEMP is required to locate the distribution keychain")
    keychain_path_file = Path(runner_temp) / "jl-appstore-signing" / "jl-keychain-path"
    if not keychain_path_file.is_file():
        fail(f"Distribution keychain path is missing at {keychain_path_file}")
    keychain = keychain_path_file.read_text().strip()
    identities = subprocess.check_output(
        ["security", "find-identity", "-v", "-p", "codesigning", keychain],
        text=True,
    )
    for line in identities.splitlines():
        if "Distribution" not in line or '"' not in line:
            continue
        return line.split('"', 2)[1]
    fail("No Apple Distribution identity is available for codesign")


def codesign_bundle(identity, bundle, entitlements_path=None, preserve=False):
    command = [
        "codesign",
        "--force",
        "--sign",
        identity,
        "--generate-entitlement-der",
        "--timestamp",
    ]
    if entitlements_path is not None:
        command.extend(["--entitlements", str(entitlements_path)])
    elif preserve:
        command.append("--preserve-metadata=identifier,entitlements,flags")
    command.append(str(bundle))
    print(f"codesign {bundle.name}")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0 and preserve:
        return codesign_bundle(identity, bundle, entitlements_path=None, preserve=False)
    detail = (result.stderr or result.stdout or "").strip()
    if result.returncode != 0 and "timestamp" in detail.lower():
        command = [arg for arg in command if arg != "--timestamp"]
        print(f"codesign {bundle.name} without timestamp")
        result = subprocess.run(command, capture_output=True, text=True)
        detail = (result.stderr or result.stdout or "").strip()
    if result.returncode != 0:
        fail(f"codesign {bundle.name} failed: {detail}")
    return result


def resign_ipa(ipa_path):
    """Re-sign an exported IPA. Xcode 26 export drops HealthKit from unsigned archives."""
    ipa = Path(ipa_path)
    if not ipa.is_file():
        fail(f"IPA was not found at {ipa}")
    identity = distribution_signing_identity()
    with tempfile.TemporaryDirectory(prefix="jl-resign-") as tmp:
        root = Path(tmp)
        run(["unzip", "-q", str(ipa), "-d", str(root)])
        apps = sorted((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            fail(f"Expected one Payload/*.app, found {[path.name for path in apps]}")
        app = apps[0]
        for bundle, entitlements in resign_plan(app):
            if not bundle.exists():
                fail(f"IPA is missing {bundle.name}")
            entitlements_path = None
            if entitlements is not None:
                if bundle.suffix == ".app":
                    if not is_enabled(entitlements.get(HEALTHKIT_KEY)):
                        fail("Resign entitlements are missing HealthKit")
                    if not isinstance(entitlements.get(HEALTHKIT_ACCESS_KEY), list):
                        fail("Resign entitlements are missing HealthKit access")
                entitlements_path = root / f"{bundle.name}.entitlements"
                with entitlements_path.open("wb") as entitlements_file:
                    plistlib.dump(entitlements, entitlements_file)
            codesign_bundle(
                identity,
                bundle,
                entitlements_path=entitlements_path,
                preserve=entitlements is None,
            )
        resigned = root / "resigned.ipa"
        run(
            [
                "ditto",
                "-c",
                "-k",
                "--norsrc",
                "--keepParent",
                str(root / "Payload"),
                str(resigned),
            ]
        )
        ipa.write_bytes(resigned.read_bytes())
    print(f"resigned {ipa} with explicit entitlements")


def self_check():
    extension_ok = {"com.apple.security.application-groups": [APP_GROUP]}
    if profile_problems(extension_ok, "extension"):
        fail("extension profile with the app group was rejected")
    if not profile_problems({}, "extension"):
        fail("extension profile without the app group was accepted")
    app_ok = {
        "com.apple.security.application-groups": [APP_GROUP],
        "com.apple.developer.healthkit": True,
        "com.apple.developer.healthkit.access": [],
        "com.apple.developer.healthkit.background-delivery": True,
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-identifiers": [ICLOUD_CONTAINER],
        "com.apple.developer.associated-domains": "*",
    }
    if profile_problems(app_ok, "app"):
        fail("complete app profile was rejected")
    wildcard_profile = {
        "com.apple.security.application-groups": [APP_GROUP],
        "com.apple.developer.healthkit": True,
        "com.apple.developer.healthkit.access": [],
        "com.apple.developer.healthkit.background-delivery": True,
        "com.apple.developer.icloud-services": "*",
        "com.apple.developer.icloud-container-environment": ["Production", "Development"],
        "com.apple.developer.icloud-container-identifiers": [ICLOUD_CONTAINER],
        "com.apple.developer.associated-domains": "*",
    }
    if profile_problems(wildcard_profile, "app"):
        fail("string wildcard iCloud services profile was rejected")
    wildcard_list = dict(wildcard_profile)
    wildcard_list["com.apple.developer.icloud-services"] = ["*"]
    if profile_problems(wildcard_list, "app"):
        fail("list wildcard iCloud services profile was rejected")
    missing_container = dict(wildcard_profile)
    missing_container["com.apple.developer.icloud-container-identifiers"] = [
        "iCloud.com.other.app"
    ]
    if not profile_problems(missing_container, "app"):
        fail("profile missing the app container was accepted")
    documents_only = dict(app_ok)
    documents_only["com.apple.developer.icloud-services"] = ["CloudDocuments"]
    if not profile_problems(documents_only, "app"):
        fail("profile without CloudKit or * was accepted")
    entitlement_problems = distribution_entitlement_problems("com.jonathanbowe.jlphysical")
    if entitlement_problems:
        fail("; ".join(entitlement_problems))
    if not profile_problems(
        {"com.apple.security.application-groups": [APP_GROUP]},
        "app",
    ):
        fail("app profile missing HealthKit was accepted")
    missing_access = dict(app_ok)
    missing_access.pop("com.apple.developer.healthkit.access")
    if not profile_problems(missing_access, "app"):
        fail("app profile missing HealthKit access was accepted")
    recorded = []
    original_api = api

    def fake_api(token, method, url, body=None):
        recorded.append((method, url))
        return 200, {"data": [], "links": {}}

    globals()["api"] = fake_api
    try:
        listed = list_capabilities("token", "24674R8P55")
    finally:
        globals()["api"] = original_api
    expected = bundle_id_capabilities_url("24674R8P55")
    if recorded != [("GET", expected)] or "limit" in expected or "?" in expected:
        fail(f"capabilities relationship request was {recorded}")
    if listed != []:
        fail("capabilities relationship should return the data array")

    app_plan = capability_plan("app")
    extension_plan = capability_plan("extension")
    if [item[0] for item in app_plan] != [
        "APP_GROUPS",
        "ASSOCIATED_DOMAINS",
        "ICLOUD",
        "HEALTHKIT",
    ]:
        fail(f"app capability plan was {app_plan}")
    if extension_plan != [("APP_GROUPS", None)]:
        fail(f"extension capability plan was {extension_plan}")
    illegal_fragments = (
        "APP_GROUP_IDS",
        "ASSOCIATED_DOMAIN_IDS",
        "XCODE_13",
        '"key": "APP_GROUPS"',
    )
    for capability_type, settings in app_plan:
        assert_settings_allowed(settings)
        rendered = json.dumps(settings)
        for fragment in illegal_fragments:
            if fragment in rendered:
                fail(f"{capability_type} payload contains {fragment}")
        if capability_type == "ICLOUD":
            options = [
                option.get("key")
                for setting in settings
                for option in setting["options"]
            ]
            if options != ["XCODE_6"] or settings[0]["key"] != "ICLOUD_VERSION":
                fail(f"iCloud payload must be ICLOUD_VERSION/XCODE_6, got {settings}")
        elif settings is not None:
            fail(f"{capability_type} must be enabled with no settings")

    invalid_settings = {
        "errors": [
            {
                "code": "ENTITY_ERROR.ATTRIBUTE.TYPE",
                "status": "409",
                "title": "An attribute in the provided entity has the wrong type",
                "detail": (
                    "'APP_GROUP_IDS' is not a valid value for the attribute "
                    "'settings/0/key'. Expected one of: 'ICLOUD_VERSION', "
                    "'DATA_PROTECTION_PERMISSION_LEVEL', 'APPLE_ID_AUTH_APP_CONSENT'"
                ),
            }
        ]
    }
    if is_duplicate_conflict(409, invalid_settings):
        fail("invalid settings 409 was treated as already enabled")
    if not is_duplicate_conflict(
        409, {"errors": [{"detail": "The bundleIdCapability already exists."}]}
    ):
        fail("duplicate 409 was not recognized")
    if is_duplicate_conflict(400, invalid_settings):
        fail("HTTP 400 was treated as a duplicate capability")

    posts = []
    patches = []

    def recording_api(token, method, url, body=None):
        if method == "POST":
            posts.append(body)
            return 201, {"data": {"id": "NEW", "attributes": {}}}
        if method == "PATCH":
            patches.append((url, body))
            return 200, {"data": {"id": "ICAP"}}
        if "bundleIdCapabilities" in url:
            return 200, {"data": [], "links": {}}
        fail(f"self-check saw unexpected {method} {url}")

    globals()["api"] = recording_api
    try:
        enable_target_capabilities("token", "24674R8P55", "app")
    finally:
        globals()["api"] = original_api
    posted_types = [
        (body["data"]["attributes"].get("capabilityType"), body["data"]["attributes"].get("settings"))
        for body in posts
    ]
    if posted_types != app_plan:
        fail(f"enable posted {posted_types}")
    if patches:
        fail(f"fresh capabilities should not be patched, got {patches}")
    joined = json.dumps(posts)
    if "/v1/capabilities?" in joined or "limit=200" in joined:
        fail("capability template lookup was issued")

    def patching_api(token, method, url, body=None):
        if method == "GET" and url == bundle_id_capabilities_url("24674R8P55"):
            return 200, {
                "data": [
                    {
                        "type": "bundleIdCapabilities",
                        "id": "ICAP",
                        "attributes": {
                            "capabilityType": "ICLOUD",
                            "settings": [
                                {
                                    "key": "ICLOUD_VERSION",
                                    "options": [{"key": "XCODE_5", "enabled": True}],
                                }
                            ],
                        },
                    }
                ],
                "links": {},
            }
        if method == "PATCH":
            patches.append((url, body))
            return 200, {"data": {"id": "ICAP"}}
        fail(f"self-check saw unexpected {method} {url}")

    globals()["api"] = patching_api
    try:
        ensure_capability("token", "24674R8P55", "ICLOUD", ICLOUD_CLOUDKIT_SETTINGS)
    finally:
        globals()["api"] = original_api
    if len(patches) != 1:
        fail(f"expected one iCloud patch, got {patches}")
    patch_url, patch_body = patches[0]
    patch_settings = patch_body["data"]["attributes"]["settings"]
    if patch_url != f"{API_ROOT}/v1/bundleIdCapabilities/ICAP":
        fail(f"iCloud patch URL was {patch_url}")
    if patch_settings != ICLOUD_CLOUDKIT_SETTINGS:
        fail(f"iCloud patch settings were {patch_settings}")

    def rejecting_api(token, method, url, body=None):
        if method == "GET":
            return 200, {"data": [], "links": {}}
        return 409, invalid_settings

    globals()["api"] = rejecting_api
    try:
        try:
            print("self-check expects the next capability enable to fail")
            ensure_capability("token", "24674R8P55", "ASSOCIATED_DOMAINS", None)
        except SystemExit:
            pass
        else:
            fail("invalid settings 409 was treated as success")
    finally:
        globals()["api"] = original_api

    admin_material = "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----\n"
    selected_id, selected_label = resolve_api_key_id(
        {
            "ADMIN_KEY_ID": " ADMINKEY01 ",
            "ADMIN_AUTH_KEY": admin_material,
            "KEY_ID": "FALLBACK01",
            "AUTH_KEY": "fallback-material",
        }
    )
    if selected_id != "ADMINKEY01" or not selected_label.startswith("admin "):
        fail("admin API key was not selected when both admin secrets are set")
    if admin_material.strip() in selected_label or "not-a-real-key" in selected_label:
        fail("API key label included key contents")
    fallback_id, fallback_label = resolve_api_key_id(
        {
            "ADMIN_KEY_ID": "ADMINKEY01",
            "ADMIN_AUTH_KEY": " \n\t",
            "KEY_ID": " FALLBACK01 ",
        }
    )
    if fallback_id != "FALLBACK01" or not fallback_label.startswith("default "):
        fail("incomplete admin API key did not fall back to KEY_ID")
    absent_id, absent_label = resolve_api_key_id({})
    if absent_id != "" or not absent_label.startswith("default "):
        fail("missing API keys did not resolve to the default label")

    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / "JLPhysical.xcarchive"
        for relative, _, _ in (
            ("Products/Applications/calorietracker.app", None, None),
            (
                "Products/Applications/calorietracker.app/PlugIns/FudAIWidgetsExtension.appex",
                None,
                None,
            ),
            (
                "Products/Applications/calorietracker.app/PlugIns/calorietrackerShare.appex",
                None,
                None,
            ),
        ):
            (archive / relative).mkdir(parents=True)
        write_archived_entitlements(archive)
        with (archive / "Products/Applications/calorietracker.app/archived-expanded-entitlements.xcent").open("rb") as xcent_file:
            expanded = plistlib.load(xcent_file)
        if expanded.get(HEALTHKIT_KEY) is not True:
            fail("archive entitlements dropped HealthKit")
        if expanded.get(HEALTHKIT_ACCESS_KEY) != []:
            fail(f"archive entitlements HealthKit access was {expanded.get(HEALTHKIT_ACCESS_KEY)}")
        if expanded.get("com.apple.security.application-groups") != [APP_GROUP]:
            fail("archive entitlements did not expand the app group")
        if expanded.get(ICLOUD_CONTAINERS_KEY) != [ICLOUD_CONTAINER]:
            fail("archive entitlements did not expand the iCloud container")
        if expanded.get(APPLICATION_IDENTIFIER_KEY) != f"{TEAM_ID}.com.jonathanbowe.jlphysical":
            fail("archive entitlements dropped application-identifier")
        if expanded.get(TEAM_IDENTIFIER_KEY) != TEAM_ID:
            fail("archive entitlements dropped the team identifier")
        if expanded.get(ICLOUD_ENVIRONMENT_KEY) != "Production":
            fail("archive entitlements must set iCloud environment to the string Production")
        if not isinstance(expanded.get(ICLOUD_ENVIRONMENT_KEY), str):
            fail("archive iCloud environment was not a string")
        widget_xcent = (
            archive
            / "Products/Applications/calorietracker.app/PlugIns/FudAIWidgetsExtension.appex/archived-expanded-entitlements.xcent"
        )
        with widget_xcent.open("rb") as widget_file:
            widget_plist = plistlib.load(widget_file)
        if widget_plist.get("com.apple.security.application-groups") != [APP_GROUP]:
            fail("widget archive entitlements did not expand the app group")
        if HEALTHKIT_KEY in widget_plist:
            fail("widget archive entitlements included HealthKit")
        if widget_plist.get(APPLICATION_IDENTIFIER_KEY) != (
            f"{TEAM_ID}.com.jonathanbowe.jlphysical.FudAIWidgetsExtension"
        ):
            fail("widget archive entitlements dropped application-identifier")
        if ICLOUD_ENVIRONMENT_KEY in widget_plist:
            fail("widget archive entitlements set an iCloud environment")

    with tempfile.TemporaryDirectory() as tmp:
        app = Path(tmp) / "Payload" / "calorietracker.app"
        (app / "PlugIns" / "FudAIWidgetsExtension.appex").mkdir(parents=True)
        (app / "PlugIns" / "calorietrackerShare.appex").mkdir(parents=True)
        (app / "Frameworks" / "Foo.framework" / "Frameworks" / "Bar.framework").mkdir(parents=True)
        steps = resign_plan(app)
        names = [path.name for path, _entitlements in steps]
        if names != [
            "Bar.framework",
            "Foo.framework",
            "FudAIWidgetsExtension.appex",
            "calorietrackerShare.appex",
            "calorietracker.app",
        ]:
            fail(f"resign order was {names}")
        if steps[0][1] is not None or steps[1][1] is not None:
            fail("framework resign steps should keep their existing entitlements")
        widget_entitlements = steps[2][1]
        share_entitlements = steps[3][1]
        app_entitlements = steps[4][1]
        if HEALTHKIT_KEY in widget_entitlements:
            fail("widget resign entitlements included HealthKit")
        if app_entitlements.get(HEALTHKIT_KEY) is not True:
            fail("app resign entitlements dropped HealthKit")
        if app_entitlements.get(HEALTHKIT_ACCESS_KEY) != []:
            fail("app resign entitlements dropped HealthKit access")
        if app_entitlements.get("com.apple.security.application-groups") != [APP_GROUP]:
            fail("app resign entitlements did not expand the app group")
        if app_entitlements.get(APPLICATION_IDENTIFIER_KEY) != (
            f"{TEAM_ID}.com.jonathanbowe.jlphysical"
        ):
            fail("app resign entitlements dropped application-identifier")
        if app_entitlements.get(ICLOUD_ENVIRONMENT_KEY) != "Production":
            fail("app resign entitlements must set iCloud environment to Production")
        if share_entitlements.get(APPLICATION_IDENTIFIER_KEY) != (
            f"{TEAM_ID}.com.jonathanbowe.jlphysical.calorietrackerShare"
        ):
            fail("share resign entitlements dropped application-identifier")
        if widget_entitlements.get(APPLICATION_IDENTIFIER_KEY) != (
            f"{TEAM_ID}.com.jonathanbowe.jlphysical.FudAIWidgetsExtension"
        ):
            fail("widget resign entitlements dropped application-identifier")
        if ICLOUD_ENVIRONMENT_KEY in widget_entitlements or ICLOUD_ENVIRONMENT_KEY in share_entitlements:
            fail("extension resign entitlements set an iCloud environment")
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

    app_entitlement_problems = distribution_entitlement_problems(
        "com.jonathanbowe.jlphysical"
    )
    if app_entitlement_problems:
        fail("; ".join(app_entitlement_problems))

    profiles_by_bundle_id = {}
    for target, bundle_resource_id in resolved:
        profile = create_profile(
            token,
            target["profile_name"],
            bundle_resource_id,
            certificate["id"],
        )
        decoded = install_profile(profile, work_dir)
        problems = profile_problems(
            decoded.get("Entitlements") or {}, target["kind"], target["bundle_id"]
        )
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
            problems = profile_problems(
                decoded.get("Entitlements") or {}, target["kind"], target["bundle_id"]
            )
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
    elif "--write-archive-entitlements" in sys.argv:
        index = sys.argv.index("--write-archive-entitlements")
        if index + 1 >= len(sys.argv):
            fail("--write-archive-entitlements requires an xcarchive path")
        write_archived_entitlements(sys.argv[index + 1])
    elif "--resign-ipa" in sys.argv:
        index = sys.argv.index("--resign-ipa")
        if index + 1 >= len(sys.argv):
            fail("--resign-ipa requires an ipa path")
        resign_ipa(sys.argv[index + 1])
    else:
        main()
