# Island Pulse — Context

## What It Is

Island Pulse is a SaaS product for Fortnite Creative island creators. It tracks island metrics via the Fortnite Data API, provides health signals, instant Telegram alerts, and competitor comparison — data not available in Epic's Creator Portal.

## Why It Exists

Epic's Creator Portal shows current metrics but no historical data, no alerts, no competitor comparison. The Fortnite Data API provides real-time data (7-day window) but requires programmatic access. Island Pulse fills this gap by storing day-level data forever (the moat) and delivering actionable insights via Telegram.

## Target User

Solo creators with 1–3 islands. Gamers who live in Discord/Telegram, not email.

## Tech Stack

- **Elixir/Phoenix** — concurrent API polling, real-time alerts via LiveView
- **Postgres** — time-series metric storage (day forever, hour 30d, minute 7d)
- **Oban + Quantum** — scheduled polling jobs (one per island)
- **Tesla** — HTTP client for Fortnite Data API
- **Telegram.Bot** — bot commands, alert delivery, daily summaries
- **ApexCharts** — JS charting in web dashboard
- **Fly.io** — deployment (`*.fly.dev` subdomain for now)

## Key Decisions

### API
- Fortnite Data API: `https://api.fortnite.com/ecosystem/v1/`
- No auth required for basic access
- Rate limiting undocumented — circuit breaker on 429 (pause all 5min), per-island backoff on other errors
- Metrics return `null` for islands with <5 unique players

### Schema
- `islands` — single source of truth per island_code (UNIQUE)
- `user_islands` — junction table with role (`primary`/`tracked`)
- Polling driven by "anyone tracks this island"
- Shared metrics across users

### Alerts
- Baseline = median(last 7 days), trend = EWMA(decay=0.3)
- Dynamic thresholds by maturity (7-14d: noisy, 15-30d: forming, 31+d: stable)
- CRITICAL immediate via Telegram, WARNING/INFO in daily digest
- Cooldown on CRITICAL: 24h unless worsens >5% or recovers

### Dead Islands
- 3 null polls (~1.5h) → first alert, keep polling 24h grace
- After day 3: weekly check-ins instead of daily summaries
- Resume automatically when data returns

### Payment (V1.5)
- Paddle (Merchant of Record, Honduras-friendly)
- One product, two price variants: Creator $9.99/mo, Pro $24.99/mo
- 7-day free trial of Creator
- Free tier: 1 island + 1 competitor (bot only)

### Dashboard
- Auth via Telegram Login Widget
- Three tabs on one page: Health Overview, Competitor Comparison, Historical Trends
- Cards auto-refresh every 30s, charts static

## MVP Scope

Build everything except payment processing, email notifications, and community features. Test on creator's own islands first. Add monetization (V1.5) when product is polished.
