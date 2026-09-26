# TestFlight Deployment Guide for JL Physical

## App Store Connect Configuration

**Apple App ID:** 6816445716  
**Team ID:** 2UMNXHG36N (Jonathan Bowe)  
**Primary Bundle ID:** com.jonathanbowe.jlphysical

## Required Bundle IDs & Capabilities

You must register these 3 bundle IDs in your Apple Developer account (team 2UMNXHG36N) with the capabilities listed below:

### 1. Main App: `com.jonathanbowe.jlphysical`

**Capabilities:**
- ✅ HealthKit
  - Read: Step Count, Active Energy Burned, Exercise Time, Workout Route
  - Write: Workouts (for training sessions)
  - Background Delivery: Enabled
- ✅ App Groups
  - `group.com.jonathanbowe.jlphysical`
- ✅ Push Notifications
- ✅ Sign In with Apple

**Info.plist Requirements:**
- `NSHealthShareUsageDescription`: "JL Physical reads your step count, workout data, and activity to track your training progress and daily movement."
- `NSHealthUpdateUsageDescription`: "JL Physical writes workout sessions to HealthKit so your training is synced across all your devices."
- `ITSAppUsesNonExemptEncryption`: `NO` (only uses standard HTTPS/Apple crypto)

### 2. Widget Extension: `com.jonathanbowe.jlphysical.FudAIWidgetsExtension`

**Capabilities:**
- ✅ App Groups
  - `group.com.jonathanbowe.jlphysical` (same group as main app)

**Note:** Widgets share data with the main app via the App Group container.

### 3. Share Extension: `com.jonathanbowe.jlphysical.calorietrackerShare`

**Capabilities:**
- ✅ App Groups
  - `group.com.jonathanbowe.jlphysical` (same group as main app)

**Note:** Share extension allows importing food photos from other apps.

## Watch App (Not Shipped in Current Build)

The following targets exist in the project but are **not dependencies of the iPhone app**, so the TestFlight archive does not build or sign them:
- `com.jonathanbowe.jlphysical.watchkitapp` (Apple Watch app)
- `com.jonathanbowe.jlphysical.watchkitapp.FudAIWatchWidgets` (Watch widget)

The `calorietracker` scheme archives the iPhone app. The iPhone target has no explicit target dependency on `FudAIWatchApp`, so Xcode does not build or sign the watch targets. The watch embed phase is empty. Watch source stays in the repo.

## App Store Connect API Setup

The TestFlight workflow uses App Store Connect API authentication with these secrets (configured in repo):

- `ADMIN_KEY_ID` and `ADMIN_AUTH_KEY`: Admin-role App Store Connect API key. Used when both are non-empty
- `KEY_ID`: Fallback App Store Connect API key ID, used when the Admin pair is not both set
- `ISSUER_ID`: Issuer ID for either key (UUID from Users and Access → Keys)
- `AUTH_KEY`: Fallback `.p8` contents, including BEGIN/END markers

## Deployment Workflow

1. **Prerequisites:**
   - All 3 bundle IDs registered in Apple Developer account (team 2UMNXHG36N)
   - App Groups capability configured: `group.com.jonathanbowe.jlphysical`
   - HealthKit capability enabled for main app with background delivery
   - App Store Connect API key secrets configured in GitHub repo

2. **Trigger Deployment:**
   ```bash
   # Manual trigger only (workflow_dispatch)
   # Go to Actions → TestFlight Deploy → Run workflow
   ```

3. **Build Process:**
   - Runs on `macos-15` with Xcode 26.3 (Swift 6.2)
   - Uses `ADMIN_KEY_ID` / `ADMIN_AUTH_KEY` when both are non-empty, otherwise `KEY_ID` / `AUTH_KEY`. The log names that pair and does not print the key id or the `.p8`. `ISSUER_ID` is the issuer for either key. Fails immediately if neither pair is usable or `ISSUER_ID` is empty. Secrets are not referenced from a job `if:`
   - Checks that the selected private key is a PEM (`-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----`) and that OpenSSL can read it, without printing the key
   - Checks that the selected key id is 10 letters/digits and `ISSUER_ID` is a UUID (not the Team ID)
   - Signs an ES256 App Store Connect JWT and GETs `/v1/bundleIds`, `/v1/apps`, `/v1/certificates`, and `/v1/profiles`. Those curls use `--globoff` so `filter[identifier]` and `filter[bundleId]` are not treated as curl globs. `altool --list-providers` cannot authenticate with an API key. A 200 from `/v1/apps` does not prove the key can create profiles
   - Sets `CFBundleVersion` from `${{ github.run_number }}` by passing `CURRENT_PROJECT_VERSION` to `xcodebuild`, so the app and embedded extensions share one build number
   - Archives **unsigned** (`CODE_SIGNING_ALLOWED=NO`). Automatic signing during `xcodebuild archive` requests an iOS App Development profile. CI has no development certificate, so that step fails with "Authentication failed: bearer token" and "No profiles for com.jonathanbowe.jlphysical" even when the JWT preflight succeeded. Bundle IDs stay on the per-target values in the Xcode project; the workflow does not pass `PRODUCT_BUNDLE_IDENTIFIER`
   - Exports a local App Store IPA with **manual** signing. The export step creates an Apple Distribution certificate (type `DISTRIBUTION`) and an `IOS_APP_STORE` profile for `com.jonathanbowe.jlphysical`, `com.jonathanbowe.jlphysical.FudAIWidgetsExtension`, and `com.jonathanbowe.jlphysical.calorietrackerShare`, installs them on the runner, and does **not** pass `-allowProvisioningUpdates`. Xcode cloud signing is a separate permission ("Access to Cloud Managed Distribution Certificate"). Run 39 could read certificates and profiles and still failed with `Cloud signing permission error`. The filename follows `PRODUCT_NAME`, checked with `build/output/*.ipa`. The `.p8` is written to `~/private_keys`, `~/.private_keys`, and `~/.appstoreconnect/private_keys`
   - Uploads that IPA to TestFlight via `xcrun altool --upload-app` (`--apiKey` / `--apiIssuer`, key file `~/private_keys/AuthKey_<selected key id>.p8`)

4. **Post-Upload:**
   - Build appears in App Store Connect → TestFlight within 5-15 minutes
   - Processing notification email sent when ready for internal testing
   - Add internal testers in App Store Connect
   - Distribute to external testers after App Review approval

## CI Build Status

The `ios-build.yml` workflow runs on every push and must pass before TestFlight deployment:

1. **Simulator Build** (Debug, iPhone 16 Pro, unsigned)
2. **Generic iOS Device Build** (Release, unsigned for validation)

Both builds must succeed before triggering the TestFlight workflow.

## Troubleshooting

### "Missing required entitlement"
- Verify all 3 bundle IDs have the correct capabilities in Apple Developer portal
- Check that App Group ID matches exactly: `group.com.jonathanbowe.jlphysical`
- Ensure HealthKit is enabled with both Read and Write permissions

### "Cloud signing permission error" / "No signing certificate iOS Distribution" / "No profiles"
- That is the export failure from run 39. Listing `/v1/certificates` and `/v1/profiles` can return HTTP 200 while Xcode cloud signing is still denied. Cloud-managed distribution certificates require a separate "Access to Cloud Managed Distribution Certificate" grant
- Export does not use cloud signing. `.github/scripts/prepare_appstore_signing.py` creates a `DISTRIBUTION` certificate, enables App Groups (and, for the app, HealthKit, iCloud, and Associated Domains), creates an App Store profile for each shipping bundle ID, and writes a manual `ExportOptions.plist`
- The existing `IOS_DISTRIBUTION` certificate is not deleted. If Apple refuses another `DISTRIBUTION` certificate, the oldest `DISTRIBUTION` certificate is removed and creation is retried once
- Profiles are checked for `group.com.jonathanbowe.jlphysical`. The app profile is also checked for HealthKit, HealthKit background delivery, the container ids in `calorietracker.entitlements` (`iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`), and associated domains. App Store profiles list `com.apple.developer.icloud-services` as `*`, which covers CloudKit and CloudDocuments. That wildcard is a match, so the script does not delete and recreate the profile for it. The app entitlements file keeps `icloud-services` as `["CloudKit"]`. `icloud-container-environment` is not set there; if it is set, distribution requires `Production`
- Capability updates use only the setting keys Apple accepts (`ICLOUD_VERSION`, `DATA_PROTECTION_PERMISSION_LEVEL`, `APPLE_ID_AUTH_APP_CONSENT`). iCloud is set to `ICLOUD_VERSION` / `XCODE_6`, which is CloudKit. App Groups, Associated Domains, and HealthKit are enabled with no settings. Group ids and domain strings are not valid setting keys. A 409 whose detail says the attribute type is wrong is a rejected payload, not an existing capability. HealthKit background delivery is already produced by the HealthKit capability; the script does not call `/v1/capabilities`

### "Invalid Provisioning Profile"
- Verify `DEVELOPMENT_TEAM = 2UMNXHG36N` in `project.pbxproj`
- Manual App Store profiles are created in the export step. `-allowProvisioningUpdates` is not used; it asks Xcode to cloud-sign
- Creating those profiles requires an API key that can POST `/v1/certificates` and `/v1/profiles` (Admin or Account Holder, with Access to Certificates, Identifiers & Profiles)

### "Authentication failed" / bearer token / "No iOS App Development provisioning profiles"
- That pair of errors comes from `GatherProvisioningInputs` during **archive**, not from a bad JWT. `xcodebuild archive` with `CODE_SIGN_STYLE=Automatic` looks up an **iOS App Development** profile. The runner has no Apple Development certificate, so Xcode tries to create one and then reports a bearer-token failure. The REST preflight can still be HTTP 200
- The workflow archives unsigned and signs at export with a certificate and App Store profiles created by the API key
- The workflow signs an ES256 JWT (`kid` = Key ID, `iss` = Issuer ID, `aud` = `appstoreconnect-v1`) and calls the App Store Connect API. It prints the HTTP status and Apple's error code, title, and detail. It does not print the token or the key
- HTTP 401 means the Key ID, Issuer ID, and `.p8` do not match, or the key was revoked
- HTTP 403 on `/v1/certificates` or `/v1/profiles` means the key cannot create the distribution certificate or the App Store profiles. That is separate from the cloud-managed distribution certificate checkbox
- Widget `com.jonathanbowe.jlphysical.FudAIWidgetsExtension` and share `com.jonathanbowe.jlphysical.calorietrackerShare` need the App Group `group.com.jonathanbowe.jlphysical`. The app also needs HealthKit, iCloud (CloudKit container `iCloud.com.jonathanbowe.jlphysical`), and associated domain `applinks:jl-physical.app`
- `ADMIN_AUTH_KEY` or `AUTH_KEY` must be the `.p8` file contents, including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`. A normal key is about 6 lines. Do not wrap the secret in extra quotes. The workflow uses the Admin pair when both `ADMIN_KEY_ID` and `ADMIN_AUTH_KEY` are non-empty
- The selected key id is 10 characters. `ISSUER_ID` is the Issuer ID UUID on the Keys page, not Team ID `2UMNXHG36N`, and it is shared by both keys
- The key must not be revoked. It has to belong to team `2UMNXHG36N`

### "Export Failed"
- Check build logs for signing or entitlement errors
- Verify all extensions have correct bundle ID prefixes
- Ensure `ITSAppUsesNonExemptEncryption = NO` in `Info.plist`
- Do not pass `PRODUCT_BUNDLE_IDENTIFIER` on the `xcodebuild` command line. That setting is applied to every target. Release IDs in the project are already `com.jonathanbowe.jlphysical`, `com.jonathanbowe.jlphysical.FudAIWidgetsExtension`, and `com.jonathanbowe.jlphysical.calorietrackerShare`

### "Processing Failed" in App Store Connect
- App icon must be 1024x1024 RGB (no alpha channel)
- All required `NSUsageDescription` keys must be in `Info.plist`
- The uploaded build number is `github.run_number` (`CURRENT_PROJECT_VERSION`). App Store Connect rejects it when that number is not higher than the newest build already uploaded for marketing version 7.1
- Check email for specific rejection reasons

## App Icon

- **Asset:** `ios/calorietracker/Assets.xcassets/AppIcon.appiconset/appicon.png`
- **Size:** 1024×1024 RGB (no alpha channel)
- **Format:** PNG
- **Design:** JL Physical branding (#FF375F on dark background)

## Health Background Delivery

JL Physical uses HealthKit background delivery to:
- Sync step count updates in real-time
- Import workout data automatically
- Update Today widget with latest activity

**Implementation:**
- `HKObserverQuery` for step count changes
- Background delivery enabled in HealthKit capability
- `UIBackgroundModes` includes `fetch` and `processing`

## Bridge Sync (Optional Feature)

JL Physical can optionally sync workout data to a Neon bridge for advanced analytics:

**Endpoints:**
- `GET /api/bridge/health` - Health check
- `GET /api/workouts?limit=50` - Fetch workout history
- `POST /api/workouts` - Create new workout
- `PUT /api/workouts/{id}` - Update existing workout
- `DELETE /api/workouts/{id}` - Delete workout
- `GET /api/steps?days=7` - Fetch steps history
- `POST /api/steps` - Sync step count

**Configuration:**
- Bridge URL: `https://jl-workout-ingest.vercel.app` (default)
- API Key: Optional, configured in app Settings
- Sync happens in background when network available

## What's Different from Upstream Fud

1. **Branding:** "JL Physical" app name and icon
2. **Team/Bundle IDs:** Team 2UMNXHG36N, bundle prefix `com.jonathanbowe.jlphysical`
3. **New Features:**
   - Program V2 training templates (5-day splits)
   - RIR-based set logging (Reps in Reserve)
   - Rest timer with audio cues (non-interrupting)
   - HealthKit steps tracking with manual sync
   - Neon bridge workout sync
4. **Removed:** Apple Watch app (not in current TestFlight build)

---

**Last Updated:** 2026-09-26  
**Xcode Version:** 26.3 (Build 17C529)  
**Swift Version:** 6.2.4  
**iOS Deployment Target:** 26.2
