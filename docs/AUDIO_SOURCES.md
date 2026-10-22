# Audio Files for Rest Timer

The rest timer requires two audio files that must be added manually before building for TestFlight.

## Required Files

Place these files in `ios/calorietracker/Resources/`:

1. **`boxing_clack.mp3`** (or .wav, .m4a)
   - Boxing stick "clack" sound
   - Plays at 10 seconds remaining
   - Duration: ~0.5-1 second
   - Suggested search: "boxing stick clack", "wood clack", "clapper"

2. **`gym_bell.mp3`** (or .wav, .m4a)
   - Round/gym bell sound
   - Plays at 0 seconds (timer complete)
   - Duration: ~1-3 seconds
   - Suggested search: "boxing bell", "gym bell", "round bell"

## Requirements

- **License**: Must be royalty-free or CC0/CC-BY licensed
- **Format**: MP3, WAV, or M4A
- **Quality**: Clear, audible over background noise
- **Mix**: Should play OVER music (not duck/pause it)

## Recommended Sources

### Freesound (CC0/CC-BY)
https://freesound.org
- Search: "boxing stick", "gym bell", "boxing bell"
- Filter by "CC0" or "CC-BY" license
- Download and attribute per license

### Zapsplat (Free with attribution)
https://www.zapsplat.com
- Search: "boxing bell", "wood clack"
- Free tier requires attribution in credits

### BBC Sound Effects Archive (CC-BY-NC)
https://sound-effects.bbcrewind.co.uk
- Non-commercial use allowed with attribution
- High-quality professional recordings

### Create Your Own
- Record actual gym equipment sounds
- Use a synthesizer/DAW to create bell tones
- Ensures CC0 licensing

## Adding to Xcode

1. Download/create the two sound files
2. Open `ios/calorietracker.xcodeproj` in Xcode
3. Right-click `calorietracker/Resources` folder
4. Select "Add Files to 'calorietracker'..."
5. Choose both audio files
6. **Check** "Copy items if needed"
7. **Check** "calorietracker" target
8. Click "Add"

Verify files appear in:
- Xcode Project Navigator under Resources
- Build Phases → Copy Bundle Resources

## Attribution

Document the source in `THIRD_PARTY_NOTICES.md`:

```markdown
## Audio Files

### Boxing Clack Sound
- **Source**: [Author name], Freesound
- **URL**: https://freesound.org/people/[author]/sounds/[id]/
- **License**: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
- **Changes**: None / Trimmed to X seconds

### Gym Bell Sound  
- **Source**: [Author name], Freesound
- **URL**: https://freesound.org/people/[author]/sounds/[id]/
- **License**: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
- **Changes**: None / Normalized volume
```

## Testing

After adding files, build and run on simulator:

1. Start a workout logging session
2. Log a set
3. Start the rest timer
4. Verify audio plays at 10s and 0s
5. Play music in background (Spotify, etc.)
6. Verify timer sounds mix over music without pausing

## Current Status

**⚠️ Audio files NOT included in repository** (binary files, licensing TBD)

You must add these files before the app can play rest timer sounds. The timer will function without them, but will be silent.

## License Compliance

- CC0: No attribution required, but recommended
- CC-BY: Attribution REQUIRED in app and documentation  
- CC-BY-NC: Attribution required, commercial use prohibited
- Custom/purchased: Follow vendor license terms

Choose CC0 or CC-BY for maximum flexibility.
