# Island Growth Advisor — Plan

## Existing System Context

- Empty project at `D:/Lab/fortnite-payout-estimator`
- Git initialized, beads initialized
- No Phoenix project yet

## Proposed Architecture

```
island_advisor/
├── lib/island_advisor/
│   ├── accounts/          # users, tiers (no payment in MVP)
│   ├── islands/           # island tracking, user_islands junction
│   ├── metrics/           # polling jobs, storage, queries, retention cleanup
│   ├── alerts/            # threshold engine, alert delivery via Telegram
│   ├── api_client/        # Fortnite Data API client (HTTP + parsing)
│   ├── telegram/          # bot commands, message formatting, daily summary
│   └── web/               # Phoenix controllers, LiveView dashboard
│       ├── dashboard/     # paid user dashboard (3 tabs)
│       └── landing/       # landing page controller
├── test/
├── config/
│   └── runtime.exs        # threshold configs, API URLs, Telegram token
└── assets/                # Tailwind CSS for web UI
```

### Dependencies

- **Phoenix 1.7+** with LiveView
- **Postgres** (Fly.io Postgres or local dev)
- **Oban** — job queue for polling, retention cleanup, daily summaries
- **Quantum** — scheduling (trigger Oban jobs on schedule)
- **Tesla** — HTTP client for Fortnite API
- **Telegram.Bot** — Telegram bot library
- **ApexCharts** — JS charting (via npm in assets)
- **Tailwind CSS** — styling

### Data Flow

```
Quantum schedule
  → Oban job (one per island, bounded concurrency = 5)
    → api_client fetch metrics from Fortnite API
      → metrics store in Postgres (metrics_day / metrics_hour / metrics_minute)
        → alerts check thresholds for this island
          → CRITICAL: send via Telegram immediately
          → WARNING/INFO: queue for daily digest
```

### Alert Engine Flow

```
1. Load threshold config from config/runtime.exs
2. Determine island's data maturity (days since first non-null metric)
3. Compute baseline = median(last 7 days of stored metrics)
4. Compute trend = EWMA(decay=0.3) over stored metrics
5. Compare current value to baseline using maturity-appropriate thresholds
6. Check cooldown state (has CRITICAL been sent in last 24h for this metric?)
7. Fire alert or add to daily digest queue
```

## Data/API/Model Changes

### Database Schema

```sql
-- Core entities
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  telegram_id BIGINT UNIQUE NOT NULL,
  tier VARCHAR(20) DEFAULT 'free',  -- free, creator, pro
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE islands (
  id BIGSERIAL PRIMARY KEY,
  island_code VARCHAR(50) UNIQUE NOT NULL,
  title TEXT,
  creator_name TEXT,
  creation_tool VARCHAR(20),  -- FNC or UEFN
  first_seen_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE user_islands (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  island_id BIGINT REFERENCES islands(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL,  -- 'primary' or 'tracked' (competitor)
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, island_id)
);

-- Metrics (three tables for different retention)
CREATE TABLE metrics_day (
  id BIGSERIAL PRIMARY KEY,
  island_id BIGINT REFERENCES islands(id) ON DELETE CASCADE,
  metric_date DATE NOT NULL,
  plays INTEGER,
  unique_players INTEGER,
  minutes_played BIGINT,
  peak_ccu INTEGER,
  favorites INTEGER,
  recommendations INTEGER,
  retention_d1 NUMERIC(5,2),
  retention_d7 NUMERIC(5,2),
  inserted_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(island_id, metric_date)
);

CREATE TABLE metrics_hour (
  id BIGSERIAL PRIMARY KEY,
  island_id BIGINT REFERENCES islands(id) ON DELETE CASCADE,
  metric_date TIMESTAMPTZ NOT NULL,
  plays INTEGER,
  unique_players INTEGER,
  minutes_played BIGINT,
  peak_ccu INTEGER,
  favorites INTEGER,
  recommendations INTEGER,
  inserted_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(island_id, metric_date)
);

CREATE TABLE metrics_minute (
  id BIGSERIAL PRIMARY KEY,
  island_id BIGINT REFERENCES islands(id) ON DELETE CASCADE,
  metric_date TIMESTAMPTZ NOT NULL,
  plays INTEGER,
  unique_players INTEGER,
  minutes_played BIGINT,
  peak_ccu INTEGER,
  favorites INTEGER,
  recommendations INTEGER,
  inserted_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(island_id, metric_date)
);

-- Alerts
CREATE TABLE alerts (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  island_id BIGINT REFERENCES islands(id) ON DELETE CASCADE,
  severity VARCHAR(20) NOT NULL,  -- critical, warning, info
  metric_name VARCHAR(50) NOT NULL,
  value NUMERIC,
  threshold_pct NUMERIC,
  direction VARCHAR(10),  -- up or down
  sent_at TIMESTAMPTZ DEFAULT now(),
  cooldown_until TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_metrics_day_island_date ON metrics_day (island_id, metric_date);
CREATE INDEX idx_metrics_day_latest ON metrics_day (island_id, metric_date DESC);
CREATE INDEX idx_metrics_hour_island_date ON metrics_hour (island_id, metric_date);
CREATE INDEX idx_alerts_user_island ON alerts (user_id, island_id, sent_at DESC);
```

### API Endpoints Used

- `GET /ecosystem/v1/islands?size={n}` — list islands with pagination
- `GET /ecosystem/v1/islands/{island_code}/metrics` — time-series metrics

## Implementation Phases

### Phase 1: Foundation
1. Phoenix project setup with Oban, Quantum, Tesla, Telegram.Bot
2. Database migrations (all tables + indexes)
3. API client module (Fortnite Data API wrapper)
4. Island polling pipeline (Oban jobs + Quantum schedule)

### Phase 2: Telegram Bot
5. Bot commands (/start, /add, /remove, /list)
6. User-island linking via user_islands junction
7. Daily summary generation and delivery
8. Dead island detection and messaging

### Phase 3: Alert Engine
9. Threshold config in runtime.exs
10. Alert evaluation logic (median baseline + EWMA trend)
11. CRITICAL immediate alerts via Telegram
12. WARNING/INFO daily digest integration
13. Cooldown logic and positive alerts

### Phase 4: Web Dashboard
14. Landing page (static, pricing, FAQ, demo screenshots)
15. Health Overview tab (metrics cards + charts)
16. Competitor Comparison tab (summary table + drill-down)
17. Historical Trends tab (time-range selector + annotations)

### Phase 5: Admin + Polish
18. LiveDashboard admin panels
19. Data retention cleanup jobs
20. Version change detection (basic)
21. Quick tips library (hardcoded, LLM-assisted generation)

## Verification Strategy

- **Unit tests:** API client parsing, alert threshold logic, EWMA computation
- **Integration tests:** polling pipeline end-to-end, bot command flows
- **Manual testing:** use real Fortnite island codes, verify alerts fire correctly
- **Self-test:** creator uses the product on their own islands for 2+ weeks

## Migration / Rollback Concerns

- Database migrations are forward-only; add columns with defaults, don't rename/delete
- Retention cleanup jobs should be idempotent (safe to re-run)
- Alert cooldown state lives in DB — survives restarts

## Risks and Trade-offs

- **No payment in MVP** — simpler to build and test, but means no real multi-user testing until V1.5
- **Single OTP app** — easier now, may need extraction of api_client later if it grows
- **Forever day-level data** — trivial at current scale, may need compression later
