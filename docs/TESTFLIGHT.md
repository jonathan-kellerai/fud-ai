# TestFlight Deployment Guide

This document lists all bundle identifiers, capabilities, and App Store Connect configuration required to deploy JL Physical to TestFlight.

## Apple Developer Team

**Team ID:** `2UMNXHG36N`  
**Team Name:** Jonathan Bowe

## Bundle Identifiers

All bundle IDs must be registered in your Apple Developer account under team `2UMNXHG36N`:

### Main App
- **Bundle ID:** `com.jonathanbowe.jlphysical`
- **Name:** JL Physical
- **Platform:** iOS

### App Extensions

#### 1. Widget Extension
- **Bundle ID:** `com.jonathanbowe.jlphysical.FudAIWidgetsExtension`
- **Name:** JL Physical Widgets
- **Type:** Widget Extension
- **Platform:** iOS

#### 2. Share Extension
- **Bundle ID:** `com.jonathanbowe.jlphysical.calorietrackerShare`
- **Name:** JL Physical Import
- **Type:** Share Extension
- **Platform:** iOS

#### 3. Watch App
- **Bundle ID:** `com.jonathanbowe.jlphysical.watchkitapp`
- **Name:** JL Physical Watch
- **Type:** WatchKit App
- **Platform:** watchOS

#### 4. Watch Widget Extension
- **Bundle ID:** `com.jonathanbowe.jlphysical.watchkitapp.FudAIWatchWidgetsExtension`
- **Name:** JL Physical Watch Widgets
- **Type:** Widget Extension
- **Platform:** watchOS

## Required Capabilities

Configure these capabilities for each bundle ID in App Store Connect:

### Main App (`com.jonathanbowe.jlphysical`)

#### HealthKit
- **Required:** Yes
- **Background Delivery:** Yes
- **Clinical Health Records:** No
- **Health Records:** Read/Write
  - Dietary Energy (Calories)
  - Dietary Protein
  - Dietary Carbohydrates
  - Dietary Fat
  - Water
  - Body Mass
  - Height
  - Active Energy Burned
  - Exercise Time
  - Step Count (with background delivery)
  - Workouts (Read/Write)

#### App Groups
- **Group ID:** `group.com.jonathanbowe.jlphysical`
- **Purpose:** Share data between main app, widgets, share extension, and watch app
- **Required for:** Widget updates, share extension, watch sync

#### iCloud
- **iCloud Containers:** `iCloud.com.jonathanbowe.jlphysical`
- **Services:** CloudKit
- **Purpose:** Optional cloud backup of diary, workouts, photos

#### Associated Domains
- **Domain:** `applinks:jl-physical.app`
- **Purpose:** Universal links for deep linking (optional)

#### Background Modes
- **Background fetch:** For periodic sync
- **Background processing:** For data processing
- **HealthKit background delivery:** For step count updates

### Widget Extension (`com.jonathanbowe.jlphysical.FudAIWidgetsExtension`)

#### App Groups
- **Group ID:** `group.com.jonathanbowe.jlphysical`
- **Purpose:** Read data from main app to display in widget

### Share Extension (`com.jonathanbowe.jlphysical.calorietrackerShare`)

#### App Groups
- **Group ID:** `group.com.jonathanbowe.jlphysical`
- **Purpose:** Share imported photos with main app

### Watch App (`com.jonathanbowe.jlphysical.watchkitapp`)

#### App Groups
- **Group ID:** `group.com.jonathanbowe.jlphysical`
- **Purpose:** Sync data with iPhone app

#### HealthKit (Watch)
- **Required:** Yes (same read/write permissions as main app)

### Watch Widget Extension (`com.jonathanbowe.jlphysical.watchkitapp.FudAIWatchWidgetsExtension`)

#### App Groups
- **Group ID:** `group.com.jonathanbowe.jlphysical`

## App Store Connect Configuration

### 1. Create App Record
1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Go to **My Apps** → **+** → **New App**
3. Fill in:
   - **Platform:** iOS
   - **Name:** JL Physical
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** Select `com.jonathanbowe.jlphysical`
   - **SKU:** `jlphysical` (or your preference)
   - **User Access:** Full Access

### 2. Create API Key for CI/CD

1. Go to **Users and Access** → **Keys** → **App Store Connect API**
2. Click **+** to generate a new key
3. **Name:** JL Physical CI
4. **Access:** App Manager (or Developer if building only)
5. Download the `.p8` file (you can only download once!)
6. Note the **Key ID** and **Issuer ID**

### 3. Set Up Provisioning Profiles

For TestFlight deployment, you need distribution provisioning profiles:

1. Go to [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources)
2. Create **App Store** provisioning profiles for:
   - `com.jonathanbowe.jlphysical` (main app)
   - `com.jonathanbowe.jlphysical.FudAIWidgetsExtension`
   - `com.jonathanbowe.jlphysical.calorietrackerShare`
   - `com.jonathanbowe.jlphysical.watchkitapp`
   - `com.jonathanbowe.jlphysical.watchkitapp.FudAIWatchWidgetsExtension`
3. Or use Fastlane Match (recommended) - see below

## GitHub Actions Secrets

Configure these secrets in your repository settings:

### Required Secrets

```
APP_STORE_CONNECT_API_KEY_ID=<Your Key ID from step 2>
APP_STORE_CONNECT_ISSUER_ID=<Your Issuer ID from step 2>
APP_STORE_CONNECT_API_KEY_CONTENT=<Contents of the .p8 file>
MATCH_PASSWORD=<Password for Fastlane Match certificate encryption>
FASTLANE_APPLE_ID=<Your Apple ID email>
BUNDLE_IDENTIFIER=com.jonathanbowe.jlphysical
TEAM_ID=2UMNXHG36N
```

### Setting Up Fastlane Match

Match manages your code signing certificates and provisioning profiles in a private git repository:

1. Create a private GitHub repository (e.g., `jlphysical-certificates`)
2. Run locally:
   ```bash
   cd ios
   bundle exec fastlane match init
   # Choose 'git' and enter your certificates repo URL
   bundle exec fastlane match appstore
   ```
3. This will:
   - Create distribution certificates
   - Create provisioning profiles for all bundle IDs
   - Encrypt and store them in the git repo
   - Ask you to set a password (save this as `MATCH_PASSWORD` secret)

## Deployment Workflow

Once all secrets are configured:

1. Go to **Actions** tab in GitHub
2. Select **TestFlight Deploy** workflow
3. Click **Run workflow**
4. Choose your branch (typically `main` or release branch)
5. Monitor the build (takes ~15-20 minutes)
6. Once complete, the build will appear in App Store Connect → TestFlight

## Testing

### Internal Testing
1. In App Store Connect, go to your app → **TestFlight** → **Internal Testing**
2. Add internal testers (up to 100, must have App Store Connect access)
3. Select the uploaded build
4. Testers receive email and can install via TestFlight app

### External Testing
1. Requires App Review (first build only)
2. Go to **TestFlight** → **External Testing**
3. Create a test group, add external testers (up to 10,000)
4. Submit for Beta App Review
5. Once approved, external testers can install

## Required App Store Metadata (for Public Release)

When ready to submit to App Store:

- App Name: JL Physical
- Subtitle: Personal Strength & Diet Tracker
- Category: Health & Fitness
- Keywords: workout, strength training, diet, calories, nutrition, fitness
- Screenshots: iPhone 6.7", iPhone 6.5", iPhone 5.5" (required)
- App Preview Video: Optional
- Description: [Your app description]
- Privacy Policy URL: Required
- Support URL: Required
- Marketing URL: Optional

## Privacy Manifest

The app includes a privacy manifest (`PrivacyInfo.xcprivacy`) declaring:
- HealthKit data usage (nutrition, workouts, steps)
- Optional iCloud backup
- No data sold to third parties
- Optional hosted AI API usage (if using Plus/Pro subscriptions)

## Troubleshooting

### Build Fails: "No signing identity found"
- Ensure Fastlane Match has run successfully
- Check `MATCH_PASSWORD` is set correctly
- Verify certificates haven't expired (1 year for development, valid until renewal for distribution)

### TestFlight Upload Fails
- Verify all bundle IDs are registered in App Store Connect
- Check that API key has "App Manager" access
- Ensure build number is incremented (can't re-upload same build number)

### HealthKit Rejected
- Ensure HealthKit usage description in `Info.plist` explains why each data type is needed
- Screenshots must show HealthKit integration
- Don't request unused HealthKit permissions

## CI Build Status (Development)

The iOS Build CI workflow runs on every push to build and test the app **unsigned** for development validation. It does not deploy to TestFlight.

- Simulator build validates code compiles
- Generic device build validates for release configuration
- Tests run on simulator

TestFlight deployment is **manual only** via `workflow_dispatch` on the **TestFlight Deploy** workflow.

## Notes

- Development team is hardcoded in `Config.xcconfig`: `DEVELOPMENT_TEAM = 2UMNXHG36N`
- Bundle IDs are also set in `Config.xcconfig`
- Xcode project uses automatic file management (PBXFileSystemSynchronizedRootGroup)
- Minimum iOS version: 17.0
- Minimum watchOS version: 10.0
- Swift 6 language mode enabled (strict concurrency)
