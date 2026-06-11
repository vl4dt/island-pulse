# Island Growth Advisor — Spec

## Problem / Opportunity

Fortnite Creative island creators have no way to track their island's performance over time. Epic's Creator Portal shows current metrics but doesn't store historical data, provide alerts, or enable competitor comparison. The Fortnite Data API provides real-time metrics but requires programmatic access and doesn't retain history beyond 7 days.

## Users / Actors

- **Solo creators** with 1–3 islands (primary target)
- **Creator** themselves — the product owner is a UEFN creator testing with their own islands

## Goals

1. Give creators historical visibility into their island's health (plays, retention, engagement)
2. Alert creators immediately when metrics drop significantly
3. Enable competitor comparison to understand relative performance
4. Build a data moat by storing day-level metrics forever
5. Provide a polished product the creator can use on their own islands before launching publicly

## Non-Goals (MVP)

- Payment processing / subscription management (V1.5)
- Email notifications (V1.5, Pro-tier feature)
- Custom domain (V2)
- Community features (V2)
- Data compression for old day-level data (V2)

## Requirements

### R1: Telegram Bot
- `/start` — onboarding, add first island
- `/add <code>` — track another island
- `/remove <code>` — stop tracking an island
- `/list` — show tracked islands with current status
- Daily summary at 6 PM UTC for each tracked island
- Island management via bot commands (no web needed for free users)

### R2: Data Pipeline
- Poll Fortnite Data API every 30 minutes for day-level metrics on all tracked islands
- Minute-level polling on-demand only (alert triggers, `/status` command)
- Store metrics in Postgres with three tables: `metrics_day` (forever), `metrics_hour` (30 days), `metrics_minute` (7 days)
- One job per island via Oban (not one big job)
- Circuit breaker on 429 (pause all polling for 5 min), per-island backoff on other errors

### R3: Alert Engine
- Dynamic thresholds by data maturity:
  - 7-14 days: critical >50%, warning 25-50%
  - 15-30 days: critical >35%, warning 20-35%
  - 31+ days: critical >25%, warning 15-25%
- Baseline = median(last 7 days), trend = EWMA(decay=0.3)
- CRITICAL alerts fire immediately via Telegram
- WARNING/INFO alerts batched into daily digest
- Cooldown on CRITICAL: 24h unless metric worsens by >5% or recovers
- Positive alerts included (plays spike, retention improving)

### R4: Dead Island Detection
- Detect when an island that was active starts returning null metrics
- 3 consecutive null polls (~1.5h) → first CRITICAL alert
- Keep polling for 24h grace period
- After day 3 of null: stop daily summaries, switch to weekly check-ins
- Resume automatically when data returns + send revival alert
- Never stop polling an island someone actively tracks

### R5: Health Signal
- Per-metric health: 🟢/🟡/🔴 for plays, unique players, D1 retention, minutes/player
- Overall combination signal (e.g., "plays growing but retention slipping")
- ⚪ insufficient data when <7 days of history

### R6: Competitor Comparison
- Free tier: 1 competitor slot; Creator: 3; Pro: 10
- Summary table with all competitors + drill-down to detailed chart comparison
- Track same metrics as own islands (shared `islands` table)

### R7: Historical Trends
- Time-range selector: 7d, 30d, 90d, 1 year, all
- Hour-level data for 7-30 day ranges, day-level for longer
- Auto-annotations: alert events on timeline
- Dual-axis charts (plays + retention)

### R8: Web Dashboard (Paid Users)
- Three tabs on one page: Health Overview, Competitor Comparison, Historical Trends
- Metrics cards auto-refresh every 30s via LiveView
- Charts static (refresh on range change or competitor add)
- ApexCharts for charting

### R9: Landing Page
- Single static page at `*.fly.dev`
- Pricing table, FAQ section, demo screenshots
- CTA buttons to Telegram bot

### R10: Admin Dashboard
- LiveDashboard for internal ops
- Panels: system health, polling stats, user stats, revenue, dead islands
- Controls: re-poll island, manual tier change, pause all polling

### R11: Schema Design
- `islands` — single source of truth per island_code (UNIQUE)
- `user_islands` — junction table with role (`primary`/`tracked`)
- Polling driven by "anyone tracks this island"
- Shared metrics across users

### R12: Daily Summary Format
- Today's numbers with vs-yesterday deltas
- Weekly trend summary
- Health signal
- Quick tip (pre-written, LLM-assisted one-time generation, then hardcoded)
- "No data yet" message for new islands below 5-player threshold

## Acceptance Criteria

1. Bot responds to all commands correctly within 3 seconds
2. Island metrics are stored within 5 minutes of API poll completion
3. CRITICAL alerts reach Telegram within 1 minute of detection
4. Daily summary sent at 6 PM UTC for each active island
5. Dead island detected within 2 hours of data loss
6. Dashboard loads within 2 seconds for paid users
7. No data gaps in day-level metrics for actively tracked islands
8. Hour-level data cleaned up after 30 days, minute-level after 7 days

## Risks

- **Fortnite API rate limiting** — undocumented limits; circuit breaker is the safety net
- **Null data for small islands** — most new islands return null; product value requires active islands
- **Paddle domain approval** — `*.fly.dev` must work with Paddle (to be verified in V1.5)
- **Telegram bot reliability** — Telegram API downtime affects all free-tier users

## Open Questions / Assumptions

- The Fortnite Data API will remain publicly accessible without auth for the foreseeable future
- `*.fly.dev` subdomain works with Paddle checkout (V1.5 concern)
- 6 PM UTC is acceptable for daily summaries globally (can add configurable time in V2)
