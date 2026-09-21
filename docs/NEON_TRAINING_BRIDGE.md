# JL Physical — Neon training bridge (thin API)

**Native fork:** https://github.com/jonathan-kellerai/fud-ai (fork of MIT Fud AI / apoorvdarshan/fud-ai)  
**Bridge host (PWA/API):** https://jl-workout-ingest.vercel.app  
**DB:** Neon project `jamie-lewis-training`

## Architecture
- **Daily driver UI:** forked Fud native (iOS SwiftUI + Android Compose) — diet, coach, local diary UX.
- **Authoritative training ledger:** Neon via this thin HTTP bridge (Program V1 completed sessions, sets, RIR/RPE).
- Diet may stay local-first in Fud OR later mirror; **training logs for coaching MUST sync** through this bridge.

## Auth (v1)
- Header: `Authorization: Bearer <BRIDGE_API_KEY>` when `BRIDGE_API_KEY` is set on Vercel.
- If unset (current gym PWA), endpoints remain open as today — tighten before shipping TestFlight/Play builds.

## Endpoints

### `GET /api/bridge/health`
Returns `{ ok: true, service: "jl-training-bridge", program: "v1" }`.

### `GET /api/workouts?limit=50`
List workouts. Optional `day` filter (program_day or title).

### `POST /api/workouts`
Body must match `WorkoutPayload`:
```json
{
  "kind": "COMPLETED",
  "program_version": "v1",
  "program_day": "Day4",
  "title": "Upper Physique",
  "units": "lb",
  "session_date": "2026-09-21",
  "conditioning": null,
  "notes": ["optional note"],
  "recorded_at_utc": "2026-09-21T18:00:00.000Z",
  "opened_at_utc": "2026-09-21T17:10:00.000Z",
  "source": "jl-fud-native",
  "sets": [
    { "exercise": "incline chest press", "load": 135, "reps": 10, "rir": 3, "rpe": null, "order": 0 }
  ]
}
```

### `GET|PUT|DELETE /api/workouts/[id]`
Fetch, correct-in-place, or delete.

## Program V1 day ids
- Day1 Lower A
- Day2 Upper Push
- Day3 Pull/Hinge (cable pull-through, not RDL)
- Day4 Upper Physique
- Day5 Lower B + Cond

## Rest timer prefs
- Large settable countdown after each logged set
- Boxing stick clack at 10s, round bell at 0
- Mix over music (do not pause Spotify)

## Attribution
Preserve MIT LICENSE + NOTICE that this fork is based on Fud AI © Apoorv Darshan.
