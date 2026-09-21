# JL Physical

Personal fork of [Fud AI](https://github.com/apoorvdarshan/fud-ai) (MIT © Apoorv Darshan) for Jonathan Bowe’s strength + diet tracking.

## Architecture

- **Daily driver:** this native iOS/Android fork (Fud UX for diet/coach/workouts).
- **Training ledger:** Neon via thin bridge at https://jl-workout-ingest.vercel.app
- **Contract:** [docs/NEON_TRAINING_BRIDGE.md](docs/NEON_TRAINING_BRIDGE.md)

We are **not** the official Fud App Store / Play listing. Keep MIT LICENSE and upstream credit in About.

## Quick bridge check

```bash
curl https://jl-workout-ingest.vercel.app/api/bridge/health
```
