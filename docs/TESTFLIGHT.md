# TestFlight Deployment Guide

This guide explains how to build JL Physical for TestFlight distribution.

## Prerequisites

### 1. Apple Developer Account
- Enroll in the Apple Developer Program ($99/year)
- Access: https://developer.apple.com

### 2. App Store Connect Setup

#### Create App Record
1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Go to "My Apps" → "+" → "New App"
3. Fill in:
   - **Platform**: iOS
   - **Name**: JL Physical (or your preferred name)
   - **Primary Language**: English (US)
   - **Bundle ID**: Select/create your bundle ID (e.g., `com.jlphysical.app`)
   - **SKU**: A unique identifier (e.g., `jlphysical-ios-001`)
   - **User Access**: Full Access

#### Enable HealthKit Capability
1. Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources)
2. Select "Identifiers"
3. Find your app's Bundle ID
4. Scroll to "HealthKit" and check the box
5. Click "Save"

### 3. App Store Connect API Key

#### Create API Key
1. In App Store Connect, go to "Users and Access" → "Keys" tab
2. Click "+" to generate a new key
3. Give it a name (e.g., "JL Physical CI/CD")
4. Set **Access**: "App Manager" or "Admin"
5. Click "Generate"
6. **Download the .p8 file immediately** (you can only download it once)
7. Note the **Key ID** and **Issuer ID** shown on the page

### 4. Required Configuration Values

You'll need these values for building:

```
BUNDLE_IDENTIFIER=com.jlphysical.app  # Your chosen bundle ID
TEAM_ID=XXXXXXXXXX                     # Find in Apple Developer account → Membership
APP_STORE_CONNECT_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  # From API key page
APP_STORE_CONNECT_API_KEY_ID=XXXXXXXXXX  # From API key page
APP_STORE_CONNECT_API_KEY_CONTENT=<.p8 file contents>  # The downloaded .p8 file
```

## Build Methods

### Option A: Automated GitHub Actions (Recommended)

#### Setup Repository Secrets
1. Go to your GitHub repository → Settings → Secrets and variables → Actions
2. Add these secrets:
   - `BUNDLE_IDENTIFIER`: Your bundle ID (e.g., `com.jlphysical.app`)
   - `TEAM_ID`: Your Apple Developer Team ID
   - `APP_STORE_CONNECT_ISSUER_ID`: From App Store Connect API key
   - `APP_STORE_CONNECT_API_KEY_ID`: From App Store Connect API key
   - `APP_STORE_CONNECT_API_KEY_CONTENT`: Full contents of the .p8 file

#### Trigger Build
1. Go to Actions tab in your repository
2. Select "TestFlight Deploy" workflow
3. Click "Run workflow"
4. The build will automatically upload to TestFlight when complete

### Option B: Local Build with Fastlane

#### Install Fastlane
```bash
sudo gem install fastlane -NV
```

#### Configure Fastlane
Create `ios/fastlane/Appfile`:
```ruby
app_identifier("com.jlphysical.app")  # Your bundle ID
apple_id("your-apple-id@email.com")
team_id("YOUR_TEAM_ID")
```

Create `ios/fastlane/Fastfile`:
```ruby
default_platform(:ios)

platform :ios do
  desc "Build and upload to TestFlight"
  lane :beta do
    # Increment build number
    increment_build_number(
      build_number: latest_testflight_build_number + 1,
      xcodeproj: "calorietracker.xcodeproj"
    )
    
    # Build
    build_app(
      scheme: "calorietracker",
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          "com.jlphysical.app" => "match AppStore com.jlphysical.app"
        }
      }
    )
    
    # Upload to TestFlight
    upload_to_testflight(
      skip_waiting_for_build_processing: true
    )
  end
end
```

#### Run Build
```bash
cd ios
fastlane ios beta
```

### Option C: Manual Build with Xcode

#### Configure Xcode
1. Open `ios/calorietracker.xcodeproj` in Xcode
2. Select the project in the navigator
3. In the "Signing & Capabilities" tab:
   - Set **Team** to your Apple Developer team
   - Set **Bundle Identifier** to your chosen ID
   - Ensure "Automatically manage signing" is checked
   - Verify HealthKit capability is present

#### Build Archive
1. In Xcode menu: Product → Archive
2. Wait for build to complete
3. In the Organizer window:
   - Select your archive
   - Click "Distribute App"
   - Choose "App Store Connect"
   - Follow the wizard to upload

## Post-Upload Steps

### 1. Configure TestFlight
1. Go to App Store Connect → TestFlight
2. Wait for the build to finish processing (10-30 minutes)
3. Add "Test Information" and "What to Test" notes
4. Submit for beta review (if required)

### 2. Invite Testers
#### Internal Testing (instant)
- Add up to 100 internal testers (must have App Store Connect access)
- They can install immediately after build processing

#### External Testing (requires review)
- Create an external test group
- Add testers by email
- Submit the build for beta review
- After approval (1-2 days), testers receive invites

### 3. Distribute to Yourself
1. Install the TestFlight app on your iPhone
2. Accept the TestFlight invitation email
3. Open TestFlight and install JL Physical
4. Grant HealthKit permissions when prompted

## Troubleshooting

### Build Fails with Code Signing Error
- Verify your Team ID is correct
- Ensure Bundle ID matches App Store Connect
- Check that capabilities (HealthKit) are enabled on the Bundle ID

### "Invalid Provisioning Profile" Error
- Bundle ID must match exactly
- Ensure HealthKit is enabled on the identifier
- Try regenerating provisioning profiles in Xcode

### TestFlight Upload Hangs
- Check App Store Connect API key has correct permissions
- Verify the .p8 file content is complete and not corrupted
- Try uploading with Xcode Organizer instead

### Missing HealthKit Permission
- Update Info.plist usage descriptions
- Ensure `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` are present
- Rebuild and re-upload

## Audio Files

The rest timer requires two audio files to be added to the Xcode project before building:

### Required Files
1. `boxing_clack.mp3` (or .wav/.m4a) — boxing stick clack sound (plays at 10s remaining)
2. `gym_bell.mp3` (or .wav/.m4a) — round/gym bell sound (plays at 0s)

### Sourcing Sounds
Use royalty-free or CC0 sounds from:
- **Freesound**: https://freesound.org (CC0/CC-BY licensed)
- **Zapsplat**: https://www.zapsplat.com (free with attribution)
- **BBC Sound Effects**: https://sound-effects.bbcrewind.co.uk (CC-BY-NC licensed)

### Adding to Xcode
1. Download the sound files
2. In Xcode, right-click `calorietracker/Resources` → "Add Files to calorietracker"
3. Select both files
4. Ensure "Copy items if needed" is checked
5. Add to target: `calorietracker`
6. Document the source and license in `THIRD_PARTY_NOTICES.md`

Example entry for `THIRD_PARTY_NOTICES.md`:
```
Boxing stick clack sound
Source: Freesound user "InspectorJ"
URL: https://freesound.org/people/InspectorJ/sounds/XXXXX/
License: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication

Gym bell sound  
Source: Freesound user "unfa"
URL: https://freesound.org/people/unfa/sounds/XXXXX/
License: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
```

## CI Status

The automated iOS build runs on every push and PR. Check the Actions tab to verify:
- ✅ App compiles for iOS Simulator
- ✅ App compiles for Generic iOS Device
- ✅ Tests pass

A green build means the app is ready to archive and upload to TestFlight.

## Support

For issues specific to JL Physical, open an issue in this repository.

For general iOS/TestFlight help:
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [App Store Connect Help](https://developer.apple.com/help/app-store-connect/)
- [Fastlane Documentation](https://docs.fastlane.tools/)
