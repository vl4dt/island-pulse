# Island Pulse

Island Pulse is a SaaS product for Fortnite Creative island creators. It tracks island metrics via the Fortnite Data API, provides health signals, instant Telegram alerts, and competitor comparison — data not available in Epic's Creator Portal.

## Prerequisites

- **Elixir 1.19+** and Erlang/OTP 26+
- **Docker** (for local Postgres) or a running Postgres 16 instance
- **Git**

## Quick Start

```bash
# 1. Clone the repo
git clone <repo-url> && cd island-pulse

# 2. Start the database
docker compose up -d

# 3. Install dependencies and set up the database
mix setup

# 4. Start the Phoenix server
mix phx.server
```

The app will be available at `http://localhost:4000`. The admin dashboard is at `http://localhost:4000/dashboard`.

## Configuration

Copy `.env.example` to `.env` and set the required values:

```bash
cp .env.example .env
```

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Yes | Your Telegram bot token (from @BotFather) |
| `SECRET_KEY_BASE` | Prod only | Phoenix secret key (`mix phx.gen.secret`) |
| `DATABASE_URL` | Prod only | Postgres connection string |
| `FORTNITE_API_BASE_URL` | No | Defaults to the Fortnite Data API |
| `DAILY_SUMMARY_HOUR` | No | Hour (UTC) for daily summaries, default 18 |
| `POLLING_DAY_INTERVAL` | No | Seconds between day-level polls, default 1800 (30min) |

## Architecture

- **Oban + Quantum** — scheduled polling jobs (one per island), cron-based cleanup and daily summaries
- **Fortnite Data API** — polled every 30 minutes; circuit breaker on 429 responses
- **Alert Engine** — median baseline + EWMA trend detection with dynamic thresholds by data maturity
- **Telegram Bot** — commands (`/add`, `/remove`, `/list`, `/status`) and alert delivery
- **Postgres** — day-level data stored forever, hour-level 30 days, minute-level 7 days

## Database

The database schema includes:

- `users` — Telegram users with subscription tier
- `islands` — Fortnite islands (single source of truth)
- `user_islands` — junction table linking users to islands (primary/tracked roles)
- `metrics_day`, `metrics_hour`, `metrics_minute` — time-series metric storage
- `alerts` — alert history with severity and cooldown tracking
- `oban_jobs` — Oban job queue

Migrations are in `priv/repo/migrations/`.

## Key Decisions

- **Alerts**: CRITICAL alerts sent immediately via Telegram; WARNING/INFO in daily digest
- **Dead islands**: After 3 null polls (~1.5h) first alert, then weekly check-ins after day 3
- **Circuit breaker**: 429 from API pauses all polling for 5 minutes
- **Free tier**: 1 island + 1 competitor, Telegram-only (no web dashboard)

## Development

```bash
# Run tests
mix test

# Check formatting and warnings
mix precommit

# Reset database (drops and recreates)
mix ecto.reset
```
