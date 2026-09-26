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

The `calorietracker` scheme already archives only the iPhone app. The iPhone target must not keep an explicit target dependency on `FudAIWatchApp`, or Xcode still builds and signs the watch targets. The watch embed phase is empty.

## App Store Connect API Setup

The TestFlight workflow uses App Store Connect API authentication with these secrets (configured in repo):

- `KEY_ID`: Your App Store Connect API key ID (e.g. `ABC123XYZ`)
- `ISSUER_ID`: Your App Store Connect issuer ID (UUID from Users and Access → Keys)
- `AUTH_KEY`: Full .p8 file contents including BEGIN/END markers

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
   - Fails the job immediately if `KEY_ID`, `ISSUER_ID`, or `AUTH_KEY` is empty (the values are not printed)
   - Checks that `AUTH_KEY` is a PEM private key (`-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----`) and that OpenSSL can read it, without printing the key
   - Checks that `KEY_ID` is 10 letters/digits and `ISSUER_ID` is a UUID (not the Team ID)
   - Calls `xcrun altool --list-providers` before archive so a bad API token fails in that step instead of during signing
   - Sets `CFBundleVersion` from `${{ github.run_number }}` by passing `CURRENT_PROJECT_VERSION` to `xcodebuild`, so the app and embedded extensions share one build number
   - Archives with automatic signing (`-allowProvisioningUpdates`). Bundle IDs stay on the per-target values in the Xcode project; the workflow does not pass `PRODUCT_BUNDLE_IDENTIFIER`
   - Exports a local App Store IPA (`destination` = `export`; the filename follows `PRODUCT_NAME`, checked with `build/output/*.ipa`)
   - Uploads that IPA to TestFlight via `xcrun altool --upload-app` (`--apiKey` / `--apiIssuer`, key file `~/private_keys/AuthKey_<KEY_ID>.p8`)

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

### "Invalid Provisioning Profile"
- Verify `DEVELOPMENT_TEAM = 2UMNXHG36N` in `project.pbxproj`
- Check that `-allowProvisioningUpdates` is in the archive command
- Confirm App Store Connect API key has Admin or App Manager role
- Enable **Access to Certificates, Identifiers & Profiles** on that key. Xcode uses it to create signing profiles

### "Authentication failed" / bearer token
- The workflow checks this with `xcrun altool --list-providers` before archive
- `AUTH_KEY` must be the `.p8` file contents, including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`. A normal key is about 6 lines. Do not wrap the secret in extra quotes
- `KEY_ID` is the 10-character Key ID. `ISSUER_ID` is the Issuer ID UUID on the Keys page, not Team ID `2UMNXHG36N`
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
