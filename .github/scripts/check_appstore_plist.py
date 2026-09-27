#!/usr/bin/env python3
"""Static checks for App Store validation failures altool reported or commonly reports.

`xcrun altool --validate-app` is not available on Linux. The TestFlight upload
step runs this against the built IPA. `--self-check` checks the source plists
and the pbxproj Release settings that Xcode merges into them.
"""

import plistlib
import re
import sys
import zipfile
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[2] / "ios"
APP_PLIST_PATH = IOS_ROOT / "calorietracker" / "Info.plist"
WIDGET_PLIST_PATH = IOS_ROOT / "FudAIWidgets" / "Info.plist"
SHARE_PLIST_PATH = IOS_ROOT / "calorietrackerShare" / "Info.plist"
PBXPROJ_PATH = IOS_ROOT / "calorietracker.xcodeproj" / "project.pbxproj"
APP_SOURCE = IOS_ROOT / "calorietracker"

SHIPPING_BUNDLE_IDS = (
    "com.jonathanbowe.jlphysical",
    "com.jonathanbowe.jlphysical.FudAIWidgetsExtension",
    "com.jonathanbowe.jlphysical.calorietrackerShare",
)

# Keys the main app actually prompts for. Photo saves use add-only, so
# NSPhotoLibraryUsageDescription is not required.
APP_USAGE_KEYS = (
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
    "NSLocalNetworkUsageDescription",
)

DISALLOWED_EXTENSION_KEYS = (
    "UIBackgroundModes",
    "UIApplicationExitsOnSuspend",
    "UIApplicationShortcutItems",
    "UIRequiresPersistentWiFi",
    "UIStatusBarHidden",
    "UIStatusBarStyle",
    "UINewsstandApp",
    "UIFileSharingEnabled",
    "UILaunchStoryboardName",
    "UIMainStoryboardFile",
    "CFBundleURLTypes",
)

REGISTER_RE = re.compile(r'register\s*\(\s*forTaskWithIdentifier:\s*"([^"]+)"')
REFRESH_RE = re.compile(r'BGAppRefreshTaskRequest\s*\(\s*identifier:\s*"([^"]+)"')
PROCESSING_RE = re.compile(r'BGProcessingTaskRequest\s*\(\s*identifier:\s*"([^"]+)"')
RELEASE_RE = re.compile(
    r"/\* Release \*/ = \{\s*isa = XCBuildConfiguration;\s*buildSettings = \{"
    r"(.*?)\};\s*name = Release;",
    re.S,
)
SETTING_RE = re.compile(r"^\s*([A-Za-z0-9_]+)\s*=\s*(.+?);\s*$")


def fail(message):
    print(f"ERROR: {message}")
    raise SystemExit(1)


def load_plist(path):
    with path.open("rb") as plist_file:
        return plistlib.load(plist_file)


def string_list(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


def nonempty_text(value):
    return isinstance(value, str) and bool(value.strip())


def swift_sources():
    return sorted(APP_SOURCE.rglob("*.swift"))


def task_identifiers():
    registered = []
    refresh = []
    processing = []
    for path in swift_sources():
        text = path.read_text(encoding="utf-8")
        registered.extend(REGISTER_RE.findall(text))
        refresh.extend(REFRESH_RE.findall(text))
        processing.extend(PROCESSING_RE.findall(text))
    return registered, refresh, processing


def parse_settings(block):
    settings = {}
    for line in block.splitlines():
        match = SETTING_RE.match(line)
        if not match:
            continue
        raw = match.group(2).strip()
        if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
            raw = raw[1:-1]
        settings[match.group(1)] = raw
    return settings


def release_settings_by_bundle_id():
    text = PBXPROJ_PATH.read_text(encoding="utf-8")
    found = {}
    for block in RELEASE_RE.findall(text):
        settings = parse_settings(block)
        bundle_id = settings.get("PRODUCT_BUNDLE_IDENTIFIER")
        if bundle_id in SHIPPING_BUNDLE_IDS:
            found[bundle_id] = settings
    return found


def merged_app_plist(file_plist, settings):
    merged = dict(file_plist)
    for key, value in settings.items():
        if not key.startswith("INFOPLIST_KEY_") or key.endswith("_Generation"):
            continue
        merged[key[len("INFOPLIST_KEY_") :]] = value
    return merged


def background_task_problems(plist, registered, refresh_ids, processing_ids):
    problems = []
    modes = string_list(plist.get("UIBackgroundModes"))
    permitted = string_list(plist.get("BGTaskSchedulerPermittedIdentifiers"))
    if "processing" in modes and not processing_ids:
        problems.append(
            "UIBackgroundModes contains processing, and no BGProcessingTaskRequest is registered"
        )
    if "processing" in modes and not permitted:
        problems.append(
            "UIBackgroundModes contains processing but BGTaskSchedulerPermittedIdentifiers is missing"
        )
    if "fetch" in modes and not refresh_ids:
        problems.append(
            "UIBackgroundModes contains fetch, and no BGAppRefreshTaskRequest is registered"
        )
    if refresh_ids and "fetch" not in modes:
        problems.append("BGAppRefreshTaskRequest requires UIBackgroundModes fetch")
    if processing_ids and "processing" not in modes:
        problems.append("BGProcessingTaskRequest requires UIBackgroundModes processing")
    missing = [identifier for identifier in registered if identifier not in permitted]
    if registered and missing:
        problems.append(
            "BGTaskSchedulerPermittedIdentifiers is missing "
            + ", ".join(missing)
        )
    return problems


def usage_problems(plist):
    problems = []
    for key in APP_USAGE_KEYS:
        if not nonempty_text(plist.get(key)):
            problems.append(f"{key} is missing or empty")
    if "ITSAppUsesNonExemptEncryption" not in plist:
        problems.append("ITSAppUsesNonExemptEncryption is missing")
    return problems


def extension_key_problems(plist, label):
    present = [key for key in DISALLOWED_EXTENSION_KEYS if key in plist]
    if not present:
        return []
    return [f"{label} Info.plist has disallowed keys: {', '.join(present)}"]


def version_problems(versions):
    """versions is a dict of bundle id -> (short version, build)."""
    problems = []
    shorts = {}
    builds = {}
    for bundle_id in SHIPPING_BUNDLE_IDS:
        pair = versions.get(bundle_id)
        if pair is None:
            problems.append(f"missing version for {bundle_id}")
            continue
        short_version, build = pair
        if not nonempty_text(short_version):
            problems.append(f"{bundle_id} CFBundleShortVersionString is missing or empty")
        if not nonempty_text(str(build) if build is not None else ""):
            problems.append(f"{bundle_id} CFBundleVersion is missing or empty")
        shorts[bundle_id] = short_version
        builds[bundle_id] = str(build) if build is not None else ""
    unique_shorts = set(shorts.values())
    unique_builds = set(builds.values())
    if len(unique_shorts) > 1:
        problems.append(f"CFBundleShortVersionString differs across targets: {shorts}")
    if len(unique_builds) > 1:
        problems.append(f"CFBundleVersion differs across targets: {builds}")
    return problems


def source_problems():
    problems = []
    registered, refresh_ids, processing_ids = task_identifiers()
    app_plist = load_plist(APP_PLIST_PATH)
    settings = release_settings_by_bundle_id()
    if set(settings) != set(SHIPPING_BUNDLE_IDS):
        problems.append(
            "Release settings missing for "
            + ", ".join(sorted(set(SHIPPING_BUNDLE_IDS) - set(settings)))
        )
    app_settings = settings.get(SHIPPING_BUNDLE_IDS[0], {})
    merged = merged_app_plist(app_plist, app_settings)
    problems.extend(background_task_problems(app_plist, registered, refresh_ids, processing_ids))
    problems.extend(usage_problems(merged))
    problems.extend(extension_key_problems(load_plist(WIDGET_PLIST_PATH), "widget"))
    problems.extend(extension_key_problems(load_plist(SHARE_PLIST_PATH), "share"))
    versions = {
        bundle_id: (
            bundle_settings.get("MARKETING_VERSION"),
            bundle_settings.get("CURRENT_PROJECT_VERSION"),
        )
        for bundle_id, bundle_settings in settings.items()
    }
    problems.extend(version_problems(versions))
    if registered != ["com.jlphysical.steps-sync"]:
        problems.append(f"unexpected BGTask identifiers: {registered}")
    return problems


def read_zip_plist(archive, name):
    with archive.open(name) as plist_file:
        return plistlib.load(plist_file)


def ipa_problems(ipa_path):
    problems = []
    registered, refresh_ids, processing_ids = task_identifiers()
    plists = {}
    with zipfile.ZipFile(ipa_path) as archive:
        for name in archive.namelist():
            if not name.endswith("Info.plist"):
                continue
            if "/Watch/" in name:
                continue
            plist = read_zip_plist(archive, name)
            bundle_id = plist.get("CFBundleIdentifier")
            if bundle_id in SHIPPING_BUNDLE_IDS:
                plists[bundle_id] = plist
    if SHIPPING_BUNDLE_IDS[0] not in plists:
        problems.append(f"IPA is missing {SHIPPING_BUNDLE_IDS[0]}")
        return problems
    app_plist = plists[SHIPPING_BUNDLE_IDS[0]]
    problems.extend(background_task_problems(app_plist, registered, refresh_ids, processing_ids))
    problems.extend(usage_problems(app_plist))
    for bundle_id, plist in plists.items():
        if bundle_id == SHIPPING_BUNDLE_IDS[0]:
            continue
        problems.extend(extension_key_problems(plist, bundle_id))
    versions = {
        bundle_id: (
            plist.get("CFBundleShortVersionString"),
            plist.get("CFBundleVersion"),
        )
        for bundle_id, plist in plists.items()
    }
    problems.extend(version_problems(versions))
    return problems


def altool_output_failed(exit_code, output):
    if exit_code != 0:
        return True
    return "UPLOAD FAILED" in output or "Failed to upload package" in output


HEALTHKIT_KEY = "com.apple.developer.healthkit"
HEALTHKIT_ACCESS_KEY = "com.apple.developer.healthkit.access"

# codesign --generate-entitlement-der stores Apple DER in signature slot -7.
# `codesign -d --entitlements -` prints that DER (blob header removed). `:-`
# used to force XML and is deprecated. security cms -D still prints an XML plist.
XML_ENTITLEMENTS_MAGIC = b"\xfa\xde\x71\x71"
DER_ENTITLEMENTS_MAGIC = b"\xfa\xde\x71\x72"
DER_CLASS_UNIVERSAL = 0
DER_CLASS_APPLICATION = 1
DER_CLASS_CONTEXT = 2
DER_TAG_BOOLEAN = 1
DER_TAG_INTEGER = 2
DER_TAG_OCTET_STRING = 4
DER_TAG_NULL = 5
DER_TAG_UTF8_STRING = 12
DER_TAG_SEQUENCE = 16
DER_TAG_SET = 17


def der_length(length):
    if length < 128:
        return bytes([length])
    encoded = length.to_bytes((length.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(encoded)]) + encoded


def der_tlv(tag, contents):
    return bytes([tag]) + der_length(len(contents)) + contents


def der_utf8(text):
    return der_tlv(0x0C, text.encode("utf-8"))


def der_bool(value):
    # DER canonical true is 0xFF. codesign rejects 0x01.
    return der_tlv(0x01, b"\xff" if value else b"\x00")


def der_array(items):
    return der_tlv(0x30, b"".join(items))


def der_pair(key, value_bytes):
    return der_tlv(0x30, der_utf8(key) + value_bytes)


def der_dict(pairs):
    # Apple encodes a dict as context-specific [16], not a universal SET.
    body = b"".join(der_pair(key, value) for key, value in sorted(pairs))
    return der_tlv(0xB0, body)


def der_entitlements(pairs):
    """Apple entitlement DER: APPLICATION [16] { INTEGER 1, dict }."""
    body = der_tlv(0x02, b"\x01") + der_dict(pairs)
    return der_tlv(0x70, body)


def der_set_dict(pairs):
    """Older entitlement DER: universal SET of key/value sequences."""
    body = b"".join(der_pair(key, value) for key, value in pairs)
    return der_tlv(0x31, body)


def _starts_with_plist(data):
    return data.startswith((b"<?xml", b"<plist", b"bplist"))


def _starts_with_der(data):
    return bool(data) and data[0] in (0x70, 0x30, 0x31, 0xB0)


def _strip_leading_display_text(data):
    """Drop codesign stderr lines such as Executable= if they were captured."""
    rest = data
    while rest:
        stripped = rest.lstrip(b"\r\n\t ")
        if stripped != rest:
            rest = stripped
            continue
        if (
            _starts_with_plist(rest)
            or _starts_with_der(rest)
            or rest.startswith((XML_ENTITLEMENTS_MAGIC, DER_ENTITLEMENTS_MAGIC))
        ):
            return rest
        newline = rest.find(b"\n")
        if newline < 0:
            return data
        line = rest[:newline]
        if not line or any(byte < 32 and byte not in (9, 13) for byte in line):
            return data
        try:
            line.decode("ascii")
        except UnicodeDecodeError:
            return data
        rest = rest[newline + 1 :]
    return data


def _split_codesign_blob(data):
    if len(data) < 8 or data[:4] not in (XML_ENTITLEMENTS_MAGIC, DER_ENTITLEMENTS_MAGIC):
        return data
    declared = int.from_bytes(data[4:8], "big")
    total = len(data)
    stripped = len(data.rstrip(b"\r\n\t "))
    # Blob length is either the whole header+payload or the payload alone.
    if declared in (total, stripped) and declared >= 8:
        return data[8:declared]
    if declared in (total - 8, stripped - 8):
        return data[8:8 + declared]
    payload = data[8:]
    if _starts_with_plist(payload) or _starts_with_der(payload):
        return payload
    return data


def _read_der_tlv(data, offset):
    if offset >= len(data):
        raise ValueError("truncated DER")
    first = data[offset]
    offset += 1
    tag_class = first >> 6
    constructed = bool(first & 0x20)
    tag = first & 0x1F
    if tag == 0x1F:
        tag = 0
        while True:
            if offset >= len(data):
                raise ValueError("truncated DER tag")
            byte = data[offset]
            offset += 1
            tag = (tag << 7) | (byte & 0x7F)
            if not byte & 0x80:
                break
    if offset >= len(data):
        raise ValueError("truncated DER length")
    length_byte = data[offset]
    offset += 1
    if length_byte & 0x80:
        count = length_byte & 0x7F
        if count == 0 or count > 4:
            raise ValueError("unsupported DER length")
        if offset + count > len(data):
            raise ValueError("truncated DER length")
        length = int.from_bytes(data[offset : offset + count], "big")
        offset += count
    else:
        length = length_byte
    end = offset + length
    if end > len(data):
        raise ValueError("truncated DER value")
    return tag_class, constructed, tag, data[offset:end], end


def _read_der_children(contents):
    children = []
    offset = 0
    while offset < len(contents):
        tag_class, constructed, tag, value, offset = _read_der_tlv(contents, offset)
        children.append((tag_class, constructed, tag, value))
    return children


def _is_der_pair(child):
    tag_class, constructed, tag, contents = child
    if tag_class != DER_CLASS_UNIVERSAL or tag != DER_TAG_SEQUENCE or not constructed:
        return False
    inner = _read_der_children(contents)
    if len(inner) != 2:
        return False
    key_class, key_constructed, key_tag, _key_contents = inner[0]
    return (
        key_class == DER_CLASS_UNIVERSAL
        and key_tag == DER_TAG_UTF8_STRING
        and not key_constructed
    )


def _is_der_dict(tag_class, tag, contents):
    # Context [16] is Apple's dict. A universal SET/SEQUENCE of pairs is the
    # older shape. An empty SEQUENCE is an empty array, not an empty dict.
    if tag_class == DER_CLASS_CONTEXT and tag == 16:
        return True
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_SET:
        children = _read_der_children(contents)
        return not children or all(_is_der_pair(child) for child in children)
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_SEQUENCE:
        children = _read_der_children(contents)
        return bool(children) and all(_is_der_pair(child) for child in children)
    return False


def _decode_der_dict(contents):
    children = _read_der_children(contents)
    # Some dumps wrap the pairs in one universal SET. Apple's own blob does not.
    if (
        len(children) == 1
        and children[0][0] == DER_CLASS_UNIVERSAL
        and children[0][2] in (DER_TAG_SET, DER_TAG_SEQUENCE)
        and not _is_der_pair(children[0])
    ):
        return _decode_der_dict(children[0][3])
    result = {}
    for child in children:
        if not _is_der_pair(child):
            raise ValueError("DER dictionary entry is not a key/value pair")
        key_tlv, value_tlv = _read_der_children(child[3])
        key = key_tlv[3].decode("utf-8")
        result[key] = _decode_der_value(*value_tlv)
    return result


def _decode_der_value(tag_class, constructed, tag, contents):
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_BOOLEAN and not constructed:
        if len(contents) != 1:
            raise ValueError("DER boolean length")
        return contents != b"\x00"
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_INTEGER and not constructed:
        if not contents:
            raise ValueError("DER integer length")
        return int.from_bytes(contents, "big", signed=True)
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_UTF8_STRING and not constructed:
        return contents.decode("utf-8")
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_OCTET_STRING and not constructed:
        return contents
    if tag_class == DER_CLASS_UNIVERSAL and tag == DER_TAG_NULL:
        return None
    if tag_class == DER_CLASS_APPLICATION and tag == 16 and constructed:
        children = _read_der_children(contents)
        if (
            len(children) == 2
            and children[0][0] == DER_CLASS_UNIVERSAL
            and children[0][2] == DER_TAG_INTEGER
        ):
            return _decode_der_value(*children[1])
        if len(children) == 1:
            return _decode_der_value(*children[0])
        raise ValueError("DER entitlements wrapper")
    if _is_der_dict(tag_class, tag, contents):
        return _decode_der_dict(contents)
    if constructed:
        return [_decode_der_value(*child) for child in _read_der_children(contents)]
    raise ValueError(f"unsupported DER tag class={tag_class} tag={tag}")


def decode_der_plist(data):
    tag_class, constructed, tag, contents, end = _read_der_tlv(data, 0)
    if data[end:].strip(b"\x00\r\n\t "):
        raise ValueError("trailing data after DER plist")
    value = _decode_der_value(tag_class, constructed, tag, contents)
    if not isinstance(value, dict):
        raise ValueError("DER plist is not a dictionary")
    return value


def _load_marked_plist(data):
    xml_start = data.find(b"<?xml")
    plist_start = data.find(b"<plist")
    binary_start = data.find(b"bplist")
    starts = [index for index in (xml_start, plist_start, binary_start) if index >= 0]
    if not starts:
        return None
    return plistlib.loads(data[min(starts) :])


def load_plist_bytes(data):
    """Parse XML, binary plist, or Apple DER from codesign / security cms."""
    payload = _split_codesign_blob(_strip_leading_display_text(data))
    if _starts_with_plist(payload):
        return plistlib.loads(payload)
    if _starts_with_der(payload):
        try:
            return decode_der_plist(payload)
        except (ValueError, UnicodeDecodeError) as error:
            preview = payload[:16].hex()
            fail(f"plist data is not a valid DER entitlement plist ({error}; prefix {preview})")
    try:
        parsed = _load_marked_plist(payload)
    except (plistlib.InvalidFileException, ValueError) as error:
        preview = payload[:16].hex()
        fail(f"plist data did not contain an XML or binary plist ({error}; prefix {preview})")
    if parsed is not None:
        return parsed
    preview = payload[:16].hex()
    fail(f"plist data did not contain an XML, binary, or DER plist (prefix {preview})")


def healthkit_entitlement_problems(entitlements, label):
    problems = []
    if not isinstance(entitlements, dict):
        return [f"{label} is not a dictionary"]
    if entitlements.get(HEALTHKIT_KEY) is not True:
        problems.append(f"{label} is missing {HEALTHKIT_KEY} = true")
    access = entitlements.get(HEALTHKIT_ACCESS_KEY)
    if not isinstance(access, list):
        problems.append(f"{label} is missing {HEALTHKIT_ACCESS_KEY} array")
    if problems:
        problems.append(f"{label} keys: {sorted(entitlements)}")
    return problems


def signed_entitlement_problems(plist):
    return healthkit_entitlement_problems(plist, "signed entitlements")


def provisioning_profile_problems(plist):
    if not isinstance(plist, dict):
        return ["provisioning profile is not a dictionary"]
    return healthkit_entitlement_problems(
        plist.get("Entitlements"), "provisioning profile"
    )


def self_check():
    problems = source_problems()
    if problems:
        fail("source plist check failed: " + "; ".join(problems))
    registered, refresh_ids, processing_ids = task_identifiers()
    rejected = {
        "UIBackgroundModes": ["fetch", "processing"],
        "NSHealthShareUsageDescription": "Read steps.",
    }
    rejected_problems = background_task_problems(rejected, registered, refresh_ids, processing_ids)
    if not any("processing" in problem for problem in rejected_problems):
        fail("processing without a processing task was accepted")
    run44 = (
        "ERROR: [altool] Validation failed (409) Missing Info.plist value.\n"
        "UPLOAD FAILED with 1 error. Failed to upload package.\n"
    )
    if not altool_output_failed(0, run44):
        fail("altool success exit with UPLOAD FAILED was accepted")
    if not altool_output_failed(1, "nothing"):
        fail("non-zero altool exit was accepted")
    if altool_output_failed(0, "Upload to TestFlight initiated"):
        fail("success log was treated as an upload failure")
    signed_ok = {
        HEALTHKIT_KEY: True,
        HEALTHKIT_ACCESS_KEY: [],
    }
    if signed_entitlement_problems(signed_ok):
        fail("signed HealthKit entitlements were rejected")
    if not signed_entitlement_problems({HEALTHKIT_KEY: True}):
        fail("signed entitlements without HealthKit access were accepted")
    if not signed_entitlement_problems({}):
        fail("signed entitlements without HealthKit were accepted")
    profile_ok = {"Entitlements": signed_ok}
    if provisioning_profile_problems(profile_ok):
        fail("profile with HealthKit was rejected")
    if not provisioning_profile_problems({"Entitlements": {HEALTHKIT_ACCESS_KEY: []}}):
        fail("profile without HealthKit true was accepted")
    junk = b"\xfa\xde\x71\x71" + plistlib.dumps(signed_ok)
    if signed_entitlement_problems(load_plist_bytes(junk)):
        fail("codesign blob prefix was not stripped")
    executable_xml = b"Executable=/tmp/calorietracker\n" + plistlib.dumps(signed_ok)
    if signed_entitlement_problems(load_plist_bytes(executable_xml)):
        fail("Executable= prefix was not stripped from XML entitlements")
    binary = plistlib.dumps(signed_ok, fmt=plistlib.FMT_BINARY)
    if signed_entitlement_problems(load_plist_bytes(binary)):
        fail("binary plist entitlements were rejected")
    healthkit_der_pairs = [
        (HEALTHKIT_KEY, der_bool(True)),
        (HEALTHKIT_ACCESS_KEY, der_array([])),
        (
            "com.apple.security.application-groups",
            der_array([der_utf8("group.com.jonathanbowe.jlphysical")]),
        ),
    ]
    signed_der = der_entitlements(healthkit_der_pairs)
    decoded_der = load_plist_bytes(signed_der)
    if signed_entitlement_problems(decoded_der):
        fail("DER HealthKit entitlements were rejected")
    if decoded_der.get("com.apple.security.application-groups") != [
        "group.com.jonathanbowe.jlphysical"
    ]:
        fail("DER string array was not decoded")
    der_blob = DER_ENTITLEMENTS_MAGIC + (len(signed_der) + 8).to_bytes(4, "big") + signed_der
    if signed_entitlement_problems(load_plist_bytes(der_blob)):
        fail("DER entitlements blob header was not stripped")
    payload_length_blob = DER_ENTITLEMENTS_MAGIC + len(signed_der).to_bytes(4, "big") + signed_der
    if signed_entitlement_problems(load_plist_bytes(payload_length_blob)):
        fail("DER blob with payload-only length was not stripped")
    executable_der = b"Executable=/tmp/calorietracker\n" + signed_der
    if signed_entitlement_problems(load_plist_bytes(executable_der)):
        fail("Executable= prefix was not stripped from DER entitlements")
    if signed_entitlement_problems(load_plist_bytes(der_set_dict(healthkit_der_pairs))):
        fail("legacy SET DER HealthKit entitlements were rejected")
    wrapped_pairs = b"".join(
        der_pair(key, value) for key, value in healthkit_der_pairs
    )
    wrapped_der = der_tlv(
        0x70,
        der_tlv(0x02, b"\x01") + der_tlv(0xB0, der_tlv(0x31, wrapped_pairs)),
    )
    if signed_entitlement_problems(load_plist_bytes(wrapped_der)):
        fail("DER entitlements wrapped in an explicit SET were rejected")
    missing_der = der_entitlements([(HEALTHKIT_ACCESS_KEY, der_array([]))])
    if not signed_entitlement_problems(load_plist_bytes(missing_der)):
        fail("DER entitlements without HealthKit were accepted")
    try:
        load_plist_bytes(b"not a plist")
    except SystemExit:
        pass
    else:
        fail("non-plist data was accepted")
    print("self-check ok")


def argument_path(flag):
    if flag not in sys.argv:
        return None
    index = sys.argv.index(flag)
    if index + 1 >= len(sys.argv):
        fail(f"{flag} requires a path")
    return Path(sys.argv[index + 1])


def main():
    if "--self-check" in sys.argv:
        self_check()
        return
    problems = []
    ran_targeted_check = False
    signed_path = argument_path("--signed-entitlements")
    if signed_path is not None:
        ran_targeted_check = True
        problems.extend(
            signed_entitlement_problems(load_plist_bytes(signed_path.read_bytes()))
        )
    profile_path = argument_path("--provisioning-profile")
    if profile_path is not None:
        ran_targeted_check = True
        problems.extend(
            provisioning_profile_problems(load_plist_bytes(profile_path.read_bytes()))
        )
    ipa_path = argument_path("--ipa")
    if ipa_path is not None:
        ran_targeted_check = True
        problems.extend(ipa_problems(ipa_path))
    if ran_targeted_check:
        if problems:
            fail("IPA check failed: " + "; ".join(problems))
        print("IPA check ok")
        return
    problems = source_problems()
    if problems:
        fail("source plist check failed: " + "; ".join(problems))
    print("source plist check ok")


if __name__ == "__main__":
    main()
