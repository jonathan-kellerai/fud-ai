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
    print("self-check ok")


def main():
    if "--self-check" in sys.argv:
        self_check()
        return
    if "--ipa" in sys.argv:
        index = sys.argv.index("--ipa")
        if index + 1 >= len(sys.argv):
            fail("--ipa requires a path")
        problems = ipa_problems(Path(sys.argv[index + 1]))
        if problems:
            fail("IPA plist check failed: " + "; ".join(problems))
        print("IPA plist check ok")
        return
    problems = source_problems()
    if problems:
        fail("source plist check failed: " + "; ".join(problems))
    print("source plist check ok")


if __name__ == "__main__":
    main()
