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

## Distribution certificate

TestFlight signs with one stored Apple Distribution certificate. Without it, every run creates a new `DISTRIBUTION` certificate whose private key dies with the runner, and Apple's per-account limit is reached after a few runs. Only the no-secrets TestFlight path ever deletes a certificate (see below); the stored-secrets path and the bootstrap workflow never do.

### Secrets

- `DIST_CERT_P12_BASE64`: base64 of a `.p12` holding the distribution certificate and its private key
- `DIST_CERT_P12_PASSWORD`: the `.p12` password
- `DIST_CERT_ID` (optional): the App Store Connect certificate id. When set, the script GETs `/v1/certificates/<id>` and checks that its serial matches the p12, its type is `DISTRIBUTION`, and it has not expired. When unset, it finds the `DISTRIBUTION` certificate whose serial matches the p12

When both p12 secrets are set, `prepare_appstore_signing.py` imports that p12 into the runner keychain and uses its certificate id for the App Store profiles. It does not create or delete any certificate, and logs only `Using stored distribution certificate id=<id> expires=<date>`. If only one of the two is set, the export step fails rather than creating a certificate. If no certificate in App Store Connect matches, the step fails and asks you to bootstrap again.

When neither is set, the export step creates one certificate. If Apple refuses because the account is at its limit, the step deletes the single oldest `DISTRIBUTION` certificate (by expiration date), logs its id and expiry, and retries once; if that retry is also refused, the step fails and lists the remaining `DISTRIBUTION` certificates. The new certificate's key is lost with the runner unless `DIST_CERT_EXPORT_PUBLIC_KEY` is set (see "Encrypted-export fallback"), so save the secrets once to end the churn.

### One-time bootstrap

The private key is generated on your machine and never goes to CI. Only the CSR is committed.

1. Generate the key and CSR (keep `dist.key` private and out of git):
   ```bash
   openssl genrsa -out dist.key 2048
   openssl req -new -key dist.key -out request.csr -subj "/CN=JL Physical Distribution/O=JL Physical/C=US"
   ```
2. Commit only the CSR to branch `ops/dist-cert-bootstrap` at `.github/dist-cert/request.csr` and push:
   ```bash
   git switch -c ops/dist-cert-bootstrap
   mkdir -p .github/dist-cert && cp request.csr .github/dist-cert/request.csr
   git add .github/dist-cert/request.csr && git commit -m "Distribution certificate CSR" && git push -u origin ops/dist-cert-bootstrap
   ```
   The push runs **Distribution certificate bootstrap** (`.github/workflows/dist-cert-bootstrap.yml`). It lists existing certificates (counts by type, plus id, name, and expiry of each `DISTRIBUTION` certificate) and POSTs one `DISTRIBUTION` certificate for the CSR. If a listed certificate already has the CSR's public key, that one is reused instead of creating another. At the account limit it fails without deleting anything.
3. Download artifact `dist-cert-public` (kept 3 days). It holds `certificate.json` with `id`, `name`, `expirationDate`, `serialNumber`, and `certificateContent` (the public DER certificate, base64):
   ```bash
   gh run download <run id> -n dist-cert-public
   python3 -c "import base64, json; open('dist.cer', 'wb').write(base64.b64decode(json.load(open('certificate.json'))['certificateContent']))"
   openssl x509 -inform DER -in dist.cer -out dist.pem
   ```
4. Build the p12 locally. The legacy algorithms keep it readable by macOS `security import`:
   ```bash
   openssl pkcs12 -export -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
     -inkey dist.key -in dist.pem -name "Apple Distribution" -out dist.p12
   base64 < dist.p12 | tr -d '\n' > p12.b64
   ```
   OpenSSL prompts for the export password. LibreSSL (`/usr/bin/openssl` on macOS) has no `-legacy` flag; drop it there, since it already uses these algorithms.
5. Save the secrets:
   ```bash
   gh secret set DIST_CERT_P12_BASE64 < p12.b64
   gh secret set DIST_CERT_P12_PASSWORD        # paste the export password at the prompt
   gh secret set DIST_CERT_ID --body "<id from certificate.json>"
   ```
6. Shred `p12.b64` and keep `dist.key` / `dist.p12` somewhere safe (you need them to re-save the secrets). Pushing the same CSR again before the secrets are set reports the existing certificate instead of creating another.

### Verification

Re-run **Distribution certificate bootstrap** (Actions → Run workflow, or push to `ops/dist-cert-bootstrap`). With both p12 secrets set it runs `--verify-stored-certificate`: it resolves the certificate id as above, checks that the p12's private key matches the certificate, fails if the certificate has expired and warns under 30 days, imports it into a temporary keychain to confirm `security find-identity -v -p codesigning` shows a Distribution identity, then deletes that keychain. It prints `stored distribution certificate OK id=<id> expires=<date>` and creates or deletes nothing in App Store Connect.

### Encrypted-export fallback

If a TestFlight run has to create a certificate (secrets unset), it can hand you that certificate's p12 instead of losing it:

1. Create an RSA key pair on your machine and store only the public half as the repository **variable** `DIST_CERT_EXPORT_PUBLIC_KEY`:
   ```bash
   openssl genrsa -out export-private.pem 4096
   openssl pkey -in export-private.pem -pubout -out export-public.pem
   gh variable set DIST_CERT_EXPORT_PUBLIC_KEY < export-public.pem
   ```
2. The run that creates a certificate encrypts `{"p12_base64", "password", "certificate_id"}` with AES-256-CBC + PBKDF2 under a random 32-byte key (stored as 64 hex characters), and encrypts that key with RSA-OAEP-SHA256. Only `dist-cert-export.enc` and `dist-cert-export.key.enc` are uploaded, as artifact `dist-cert-export-encrypted` (kept 3 days). Without the variable the run warns that the key will be lost and the next run will create another certificate.
3. Decrypt and save the secrets:
   ```bash
   gh run download <run id> -n dist-cert-export-encrypted
   openssl pkeyutl -decrypt -inkey export-private.pem -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
     -in dist-cert-export.key.enc -out export.key
   openssl enc -d -aes-256-cbc -pbkdf2 -pass file:export.key -in dist-cert-export.enc -out export.json
   python3 -c "import json; d = json.load(open('export.json')); open('p12.b64', 'w').write(d['p12_base64'])"
   gh secret set DIST_CERT_P12_BASE64 < p12.b64
   python3 -c "import json; print(json.load(open('export.json'))['password'], end='')" | gh secret set DIST_CERT_P12_PASSWORD
   python3 -c "import json; print(json.load(open('export.json'))['certificate_id'], end='')" | gh secret set DIST_CERT_ID
   rm -f export.key export.json p12.b64
   ```
   That p12 was built on the runner. If `security import` rejects it during verification, re-export it locally with the legacy flags from step 4 of the bootstrap.

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
   - Exports a local App Store IPA with **manual** signing. The export step imports the stored Apple Distribution certificate (type `DISTRIBUTION`; see "Distribution certificate"), or creates one when those secrets are unset, and creates an `IOS_APP_STORE` profile for `com.jonathanbowe.jlphysical`, `com.jonathanbowe.jlphysical.FudAIWidgetsExtension`, and `com.jonathanbowe.jlphysical.calorietrackerShare`, installs them on the runner, and does **not** pass `-allowProvisioningUpdates`. Xcode cloud signing is a separate permission ("Access to Cloud Managed Distribution Certificate"). Run 39 could read certificates and profiles and still failed with `Cloud signing permission error`. The filename follows `PRODUCT_NAME`, checked with `build/output/*.ipa`. The `.p8` is written to `~/private_keys`, `~/.private_keys`, and `~/.appstoreconnect/private_keys`
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

### "Missing required entitlement" / "Missing com.apple.developer.healthkit entitlement"
- Verify all 3 bundle IDs have the correct capabilities in Apple Developer portal
- Check that App Group ID matches exactly: `group.com.jonathanbowe.jlphysical`
- Ensure HealthKit is enabled with both Read and Write permissions
- The archive is unsigned (`CODE_SIGNING_ALLOWED=NO`), so Xcode never writes `archived-expanded-entitlements.xcent`. Run 46 wrote that file before export, and Xcode 26 still signed the IPA without `com.apple.developer.healthkit`
- Before `-exportArchive`, `prepare_appstore_signing.py --write-archive-entitlements` expands `calorietracker.entitlements`, the widget entitlements, and the share entitlements into each bundle's `archived-expanded-entitlements.xcent`. The app file sets `com.apple.developer.healthkit` to true and `com.apple.developer.healthkit.access` to an empty array. `$(PRODUCT_BUNDLE_IDENTIFIER)` and `$(APP_GROUP_IDENTIFIER)` are substituted first
- After export, `prepare_appstore_signing.py --resign-ipa` re-signs frameworks (keeping their entitlements), then the widget and share appexes, then the app. Each of those three signatures gets `application-identifier` set to `2UMNXHG36N.` plus that target's bundle id, and `com.apple.developer.team-identifier` set to `2UMNXHG36N`. The app signature also keeps HealthKit and sets `com.apple.developer.icloud-container-environment` to the string `Production`. The source entitlements file does not set that environment, so a local development build is not forced to Production. The embedded profile from export is left in place
- HealthKit is enabled on the App ID the same way as iCloud and App Groups (capability type `HEALTHKIT`, no settings). Profiles named `JL Physical CI *` are deleted and created again on every run after that enable step, so a capability change is in the profile that export uses
- After export, and before the upload step, the workflow runs `codesign -d --entitlements - --xml` on `Payload/*.app` and each shipping appex, and `security cms -D` on the app's `embedded.mobileprovision`. Run 48 (https://github.com/jonathan-kellerai/fud-ai/actions/runs/36327294449) re-signed successfully, then `codesign` without `--xml` wrote a `[Dict]` / `[Key]` text dump. Run 49 (https://github.com/jonathan-kellerai/fud-ai/actions/runs/36328213844) passed that gate and Apple rejected the upload: the re-sign had dropped `application-identifier` from the app, widget, and share extension, and the app signature had an empty `com.apple.developer.icloud-container-environment`. The checker accepts the text dump, XML, a binary plist, and Apple DER. If `--xml` is rejected, the workflow retries without it. The job fails unless the app signature and the profile both have `com.apple.developer.healthkit` = true and `com.apple.developer.healthkit.access` as an array, the app signature has `application-identifier` of `TeamID.bundleId` with a matching team identifier, and, when iCloud is present, `com.apple.developer.icloud-container-environment` is the string `Production`. Each appex must have the same style of `application-identifier`. `Info.plist` already has `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`

### "Cloud signing permission error" / "No signing certificate iOS Distribution" / "No profiles"
- That is the export failure from run 39. Listing `/v1/certificates` and `/v1/profiles` can return HTTP 200 while Xcode cloud signing is still denied. Cloud-managed distribution certificates require a separate "Access to Cloud Managed Distribution Certificate" grant
- Export does not use cloud signing. `.github/scripts/prepare_appstore_signing.py` installs the stored `DISTRIBUTION` certificate (or creates one when the stored secrets are unset), enables App Groups (and, for the app, HealthKit, iCloud, and Associated Domains), creates an App Store profile for each shipping bundle ID, and writes a manual `ExportOptions.plist`
- With `DIST_CERT_P12_BASE64` / `DIST_CERT_P12_PASSWORD` set, the stored certificate is imported and no certificate is created or deleted. Without them, one `DISTRIBUTION` certificate is created per run; if Apple refuses another, the oldest `DISTRIBUTION` certificate is deleted and creation is retried once. The existing `IOS_DISTRIBUTION` certificate is never deleted. See "Distribution certificate"
- Profiles are checked for `group.com.jonathanbowe.jlphysical`. The app profile is also checked for HealthKit, HealthKit access (an array, including an empty one), HealthKit background delivery, the container ids in `calorietracker.entitlements` (`iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`), and associated domains. App Store profiles list `com.apple.developer.icloud-services` as `*`, which covers CloudKit and CloudDocuments. That wildcard is a match, so the script does not delete and recreate the profile for it. The app entitlements file keeps `icloud-services` as `["CloudKit"]`. `icloud-container-environment` is not set in that file. The App Store re-sign sets it to the string `Production` on the app signature. A profile that lists both Production and Development is still valid
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

### "Missing Info.plist value" / BGTaskSchedulerPermittedIdentifiers / "UPLOAD FAILED" and the job still succeeded
- Run 44 reached Apple with `UIBackgroundModes` `processing` and no `BGTaskSchedulerPermittedIdentifiers`. The only registered task is `com.jlphysical.steps-sync`, a `BGAppRefreshTask` (`fetch`), scheduled from `AppDelegate`. `processing` is not declared
- `altool` can print `UPLOAD FAILED` and still exit 0. The upload step treats that text, `Failed to upload package`, or a non-zero exit as failure and does not print "Upload to TestFlight initiated"
- Before upload, `.github/scripts/check_appstore_plist.py` checks the IPA for the app usage strings, `ITSAppUsesNonExemptEncryption`, matching `CFBundleShortVersionString` and `CFBundleVersion` on the app, widget, and share extension, and extension keys Apple rejects. Photo saves are add-only, so the required photo key is `NSPhotoLibraryAddUsageDescription`

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
