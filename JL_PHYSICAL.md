# JL Physical

Personal fork of [Fud AI](https://github.com/apoorvdarshan/fud-ai) (MIT © Apoorv Darshan) for Jonathan Bowe's strength + diet tracking.

## Architecture

- **Daily driver:** this native iOS/Android fork (Fud UX for diet/coach/workouts).
- **Training ledger:** Neon via thin bridge at https://jl-workout-ingest.vercel.app
- **Contract:** [docs/NEON_TRAINING_BRIDGE.md](docs/NEON_TRAINING_BRIDGE.md)

We are **not** the official Fud App Store / Play listing. Keep MIT LICENSE and upstream credit in About.

## Implemented Features (iOS)

### ✅ Neon Bridge Integration
- Bridge health check endpoint
- POST completed workouts with Program V2 format
- Workout sync queue with offline retry
- Edit/delete support via bridge API
- Steps sync: POST daily totals to `/api/steps`

### ✅ Program V2 Templates
- 5-day program templates built-in (Day1_LowerA through Day5_LowerB_Cond)
- Conditioning-first block on every day
- RIR-first set logging (RPE optional)
- Load suggestions from program-v2.json starting loads
- Double progression support

### ✅ Rest Timer
- Large settable countdown (defaults from program V2)
- Boxing stick clack at 10 seconds remaining
- Gym bell at 0 seconds
- Audio plays over music (AVAudioSession .ambient + .mixWithOthers)
- Background notification fallback
- **Note**: Audio files must be added manually (see `docs/AUDIO_SOURCES.md`)

### ✅ Steps Tracking
- HealthKit integration for daily step count
- De-duplicated totals (iPhone + Apple Watch via HKStatisticsCollectionQuery)
- America/New_York calendar days per spec
- POST to `/api/steps` with source `jl-fud-native-healthkit`
- Sync on app open/foreground
- HKObserverQuery with background delivery (hourly)
- BGAppRefreshTask fallback
- 7-day view with 10,000 steps/day target

### ✅ Rebranding
- Display name: "JL Physical"
- Keeps Fud visual design (#FF375F coral, near-black canvas)
- MIT license preserved with credit to Apoorv Darshan

### ✅ Settings
- Bridge base URL configuration (default: https://jl-workout-ingest.vercel.app)
- Optional Bearer API key
- Test connection button

### ✅ CI/CD
- GitHub Actions: iOS build verification (simulator + generic device)
- TestFlight workflow (manual trigger)
- See `docs/TESTFLIGHT.md` for setup guide

### 🚧 Android
- Out of scope for this branch (iOS target only)

## Quick bridge check

```bash
curl https://jl-workout-ingest.vercel.app/api/bridge/health
```

## TestFlight Setup

See [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) for complete instructions on:
- Creating App Store Connect app record
- Enabling HealthKit capability
- Required secrets for automated builds
- Local build with Xcode or Fastlane
- Adding audio files for rest timer

## Configuration

Edit `ios/Config.xcconfig` to set:
- `PRODUCT_BUNDLE_IDENTIFIER`: Your bundle ID
- `DEVELOPMENT_TEAM`: Your Apple Developer Team ID
- `APP_DISPLAY_NAME`: App name (default: JL Physical)
