# Island Growth Advisor — Technical Implementation Plan

> **Status:** Updated 2026-06-11 to reflect actual codebase state. Phase 1 (Foundation) is partially implemented; this plan describes what remains.

---

## 1. Existing System Context

### What Exists Today

Phoenix 1.8 project with core scaffolding in place. The data pipeline skeleton exists — DB schema, API client, polling jobs, alert engine, and Telegram bot are all coded but **not fully wired together**. No web dashboard or landing page yet. No domain tests.

### File Tree (relevant paths)

```
lib/
├── island_pulse.ex                              # App root module
├── island_pulse/application.ex                  # OTP supervisor tree (Oban + Quantum wired in)
├── island_pulse/repo.ex                         # Postgres repo
├── island_pulse/mailer.ex                       # Swoosh mailer (unused — email is V1.5)
├── island_pulse/fortnite_api.ex                 # API client (Req-based, circuit breaker via :persistent_term)
├── island_pulse/accounts/
│   ├── accounts.ex                              # Context: get_or_create_user, list_users, tier management
│   └── user.ex                                  # Schema: telegram_id (unique), tier
├── island_pulse/islands/
│   ├── islands.ex                               # Context: get_or_create_island, link/unlink, counts, version check
│   ├── island.ex                                # Schema: island_code (unique), title, creator, tool
│   └── user_island.ex                           # Schema: junction with role (primary/tracked)
├── island_pulse/metrics/
│   ├── metrics.ex                               # Context: upsert_day/hour_metric, latest, maturity, median, ewma, cleanup
│   ├── metric_day.ex                            # Schema: forever retention
│   ├── metric_hour.ex                           # Schema: 30d retention
│   ├── metric_minute.ex                         # Schema: 7d retention (not yet used in polling)
│   ├── poll_island_job.ex                       # Oban worker: one job per island
│   ├── poll_all_islands_job.ex                  # Oban trigger: enqueues PollIslandJob per tracked island
│   └── cleanup_job.ex                           # Oban worker: retention cleanup (hour/minute tables)
├── island_pulse/alerts/
│   ├── alert_engine.ex                          # Median baseline, dynamic thresholds, cooldown, dead island stub
│   └── alert.ex                                 # Schema: severity, metric_name, value, direction, cooldown
└── island_pulse/telegram/
    ├── bot.ex                                   # Command handlers + message formatting + alert delivery
    └── daily_summary_job.ex                     # Oban worker: 6 PM UTC daily digest

lib/island_pulse_web/
├── router.ex                                    # Only "/" → PageController (default Phoenix page)
├── endpoint.ex                                  # Standard Phoenix endpoint
├── telemetry.ex                                 # Telemetry setup
├── controllers/page_controller.ex               # Default home page
└── components/
    ├── core_components.ex                       # Standard Phoenix core components
    └── layouts.ex                               # Standard layouts

priv/repo/migrations/
└── 20260611092600_create_core_tables.exs        # All tables + Oban migration (single migration)

config/
├── dev.exs                                      # Dev config + Oban crontab (30m poll, hourly cleanup, 6PM summary)
└── runtime.exs                                  # Alert thresholds, polling config, API URLs, Telegram token

test/                                            # Only default Phoenix controller tests (no domain tests yet)
```

### What Works Today

| Component | Status | Notes |
|-----------|--------|-------|
| **DB schema** | ✅ Complete | All tables in single migration with proper indexes |
| **API client** | ✅ Complete | `FortniteApi` with Req, parsing, circuit breaker on 429 |
| **Polling pipeline** | ⚠️ Partial | `PollAllIslandsJob` → `PollIslandJob` chain works (day + hour metrics). Alert eval NOT wired in. |
| **Alert engine** | ⚠️ Partial | Threshold eval, cooldown, dead island stub exist. EWMA not integrated. Not called from polling. |
| **Telegram bot** | ✅ Complete | `/start`, `/help`, `/add`, `/track`, `/remove`, `/list`, `/status` commands work |
| **Daily summary** | ✅ Complete | Oban cron at 6 PM UTC with rotating tips |
| **Config** | ✅ Complete | runtime.exs has all configurable parameters |

### What's Missing / Needs Work

| Gap | Severity | Impact |
|-----|----------|--------|
| Alert evaluation NOT wired into `PollIslandJob` | 🔴 Critical | No alerts fire — core product feature broken |
| Dead island state machine incomplete | 🟡 High | Detection stub exists but no grace period, weekly check-ins, auto-resume |
| EWMA trend not integrated into alert eval | 🟡 High | Only median baseline used; gradual declines missed |
| No health signal logic (🟢/🟡/🔴) | 🟡 High | Spec requirement R5 not implemented |
| No domain tests | 🟡 High | No test coverage on core logic |
| Oban crontab missing from prod config | 🟡 High | Jobs won't run in production |
| Minute-level polling not implemented | 🟢 Medium | Spec says "on-demand only" — lower priority |
| No web dashboard or landing page | 🟢 Medium | Phase 4 feature |
| No LiveDashboard admin panels | 🟢 Medium | Phase 5 feature |
| Unused deps (Tesla, Hackney) in mix.exs | 🔵 Low | Code uses Req, not Tesla |

---

## 2. Proposed Architecture

The current architecture is sound — no structural changes needed. The plan focuses on **wiring up** the existing pieces and adding the missing surfaces.

```
┌─────────────────────────────────────────────┐
│              Quantum (cron)                  │
│                                              │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ PollAllJob   │  │ DailySummary │          │
│  │ (every 30m)  │  │ Job (6PM)    │          │
│  └──────┬───────┘  └──────┬───────┘         │
└─────────┼────────────────┼──────────────────┘
          │                │
          ▼                │
   ┌──────────────┐        │
   │PollIslandJob │        │
   │(per island)  │        │
   └──────┬───────┘        │
          │                │
          ▼                │
   ┌──────────────┐        │
   │ AlertEngine  │        │
   │ evaluate/1   │        │
   └──────┬───────┘        │
          │                │
     ┌────┴─────┐          │
     ▼          ▼          │
  ┌──────┐  ┌────────┐    │
  │CRIT- │  │WARN/  │    │
  │ICAL  │  │INFO   │    │
  │(now) │  │(batch)│    │
  └──┬───┘  └──┬────┘    │
     │         │         │
     ▼         ▼         ▼
  ┌──────────────────────┐
  │   Telegram Bot       │
  │ (send_critical_alert │
  │  / daily summary)    │
  └──────────────────────┘
```

### Key Architectural Decisions

1. **No structural refactoring needed** — the existing context separation (Accounts, Islands, Metrics, Alerts, Telegram) is clean and follows Phoenix conventions.
2. **Alert wiring is the critical path** — everything downstream depends on `PollIslandJob` calling `AlertEngine.evaluate/1`.
3. **Health signals are computed at alert eval time** — no separate job needed; derive from alert results.
4. **No new DB migration needed for Phase 2** — the existing schema supports alert wiring, health signals (derived), and dead island state machine.
5. **Minute-level polling deferred** — spec says "on-demand only"; implement when dashboard needs it.

---

## 3. Phased Implementation Plan

### Phase 1: Critical Wiring (Unblock everything)

**Goal:** Make the alert pipeline actually fire. This unblocks dead island detection, health signals, integration tests, and dashboard work.

#### 1.1 Wire Alert Evaluation into PollIslandJob

**File:** `lib/island_pulse/metrics/poll_island_job.ex`

After metrics upsert (the `Enum.each(parsed, ...)` block), add:

```elixir
# After upserting metrics, evaluate alerts
case AlertEngine.evaluate(island) do
  [] ->
    {:ok, :poll_complete}

  alerts ->
    # Get users who track this island
    user_ids = Islands.list_user_ids_for_island(island.id)

    Enum.each(alerts, fn alert_map ->
      Enum.each(user_ids, fn user_id ->
        case Accounts.get_user_by_id(user_id) do
          %Accounts.User{} = user ->
            AlertEngine.save_alert(user, alert_map)

            case alert_map.severity do
              "critical" ->
                IslandPulse.Telegram.Bot.send_critical_alert(
                  user.telegram_id,
                  island.title || island.island_code,
                  alert_map.metric_name,
                  Decimal.to_string(alert_map.value),
                  alert_map.direction,
                  Decimal.to_string(alert_map.threshold_pct)
                )

              _ -> :ok # WARN/INFO batched in daily summary
            end

          nil -> :ok
        end
      end)
    end)

    {:ok, :poll_complete}
end
```

**New helper needed:** `Islands.list_user_ids_for_island/1` — query `user_islands` for user IDs tracking a given island.

#### 1.2 Add EWMA Trend Integration to Alert Engine

**File:** `lib/island_pulse/alerts/alert_engine.ex`

The `Metrics.ewma/2` function exists but isn't used in alert evaluation. Add a secondary check: if the median baseline says "no change" but the EWMA trend shows a sustained decline over the last N points, escalate to WARNING.

```elixir
# In evaluate/1, after pct_change check:
ewma_trend = Metrics.ewma_trend(island, field, 7)

case {pct_change_severity, ewma_trend} do
  {:none, :declining} -> {:warning, "down"}  # EWMA caught what median missed
  {severity, _} when severity != :none -> severity  # Median already flagged it
  {:none, _} -> :none
end
```

**New helper needed:** `Metrics.ewma_trend/3` — returns `:stable`, `:declining`, or `:growing` based on EWMA direction.

#### 1.3 Add Health Signal Logic

**File:** `lib/island_pulse/alerts/alert_engine.ex` (or new `health_signal.ex`)

After alert evaluation, compute a health signal for the island:

```elixir
def compute_health_signal(island) do
  critical_count = count_recent_alerts(island, "critical", hours: 24)
  warning_count = count_recent_alerts(island, "warning", hours: 24)
  dead? = is_dead_island?(island)

  cond do
    dead? -> :dead
    critical_count > 0 -> :unhealthy
    warning_count >= 3 -> :degraded
    true -> :healthy
  end
end
```

This signal is used in daily summaries, `/status` output, and later the web dashboard.

#### 1.4 Add Prod Oban Crontab

**File:** `config/runtime.exs` (inside the `if config_env() == :prod` block)

Add Oban crontab configuration that reads from env vars:

```elixir
config :island_pulse, Oban,
  engine: Oban.Engines.Basic,
  repo: IslandPulse.Repo,
  queues: [default: 5, polling: 5, alerts: 3],
  crontab: [
    {"*/30 * * * *", IslandPulse.Metrics.PollAllIslandsJob},
    {"0 * * * *", IslandPulse.Metrics.CleanupJob},
    {"0 18 * * *", IslandPulse.Telegram.DailySummaryJob}
  ]
```

Note: The dev config already has this; prod needs it too. Currently `runtime.exs` sets Oban-related config but NOT the crontab — that's only in `dev.exs`.

---

### Phase 2: Dead Island State Machine + Tests

**Goal:** Implement the dead island detection flow and establish test coverage.

#### 2.1 Dead Island State Machine

**File:** `lib/island_pulse/alerts/alert_engine.ex` (expand existing stub)

The spec defines a state machine:

```
Active → Null Poll 1 → (grace period) → Null Poll 3 → Dead
Dead → Weekly Check-in → (data returns) → Active
Dead → Weekly Check-in → (still null) → Dead (continue checking)
```

Implementation approach:

- Track `null_poll_count` in the `islands` table (requires **new migration**).
- On each poll, if `plays == nil` for an island that previously had data, increment `null_poll_count`.
- When `null_poll_count >= 3`, mark island as dead and send CRITICAL alert.
- Weekly check-in: add a new Oban job that runs weekly, checks dead islands, sends notification, and reactivates if data returns.

**Migration needed:**

```elixir
alter table(:islands) do
  add :null_poll_count, :integer, default: 0, null: false
  add :status, :string, size: 20, default: "active", null: false
end
```

#### 2.2 Domain Unit Tests

**Files:** New test files under `test/island_pulse/`

Test the core logic without mocking the full pipeline:

- **FortniteApi tests:** Parsing of various response shapes (normal, empty, rate-limited). Circuit breaker open/close transitions.
- **AlertEngine tests:** Threshold evaluation with known data (noisy/forming/stable maturity levels). Cooldown enforcement. Dead island detection.
- **Metrics tests:** Median computation. EWMA computation. Data maturity calculation.
- **Islands tests:** Version change detection. User-island linking/unlinking.

Use `start_supervised!([IslandPulse.Repo])` in test setup for isolated DB access.

#### 2.3 Bot Command Tests

**File:** `test/island_pulse/telegram/bot_test.exs`

Test the command routing and message formatting:

- `/add` with valid code → island linked, poll job enqueued
- `/add` with empty code → error message
- `/add` exceeding free tier limit → rejection message
- `/status` for island with data → formatted metrics
- `/status` for island without data → "no data" message

---

### Phase 3: Cleanup + Polish

**Goal:** Remove unused dependencies, add missing features, harden for production.

#### 3.1 Remove Unused Dependencies

**File:** `mix.exs`

Remove from deps list:
- `{:tesla, "~> 1.11"}` — code uses Req, not Tesla
- `{:hackney, "~> 1.9"}` — only used by Tesla

Run `mix deps.unlock --unused` as part of precommit to catch future drift.

#### 3.2 Version Change Detection Integration

**File:** `lib/island_pulse/metrics/poll_island_job.ex`

The `Islands.check_version_change/2` function exists but isn't called. Wire it in:

```elixir
# In PollIslandJob, after get_or_create_island returns an existing island:
case Islands.check_version_change(island, %{title: parsed_title, creation_tool: parsed_tool}) do
  {:changed, changes} ->
    # Notify users tracking this island about the change
    notify_version_change(island, changes)

  {:unchanged} -> :ok
end
```

#### 3.3 Cleanup Job Verification

**File:** `test/island_pulse/metrics/cleanup_job_test.exs`

Verify that:
- Hour metrics older than 30 days are deleted
- Minute metrics older than 7 days are deleted
- Day metrics are never deleted (forever retention)

---

### Phase 4: Web Dashboard (Future — separate epic)

**Goal:** Landing page + island detail dashboard with charts.

This is a substantial feature and should be its own epic. Key components:

1. **Landing page** (`/`) — Hero section, features, "Add your island" CTA
2. **Island list** (`/islands`) — Table of user's islands with health signals
3. **Island detail** (`/islands/:code`) — ApexCharts time series, alerts history, competitor comparison
4. **Authentication** — Telegram login flow (deeplink from bot)

No migration needed — the existing schema supports all queries. New LiveViews only.

---

### Phase 5: Admin Panels (Future — separate epic)

**Goal:** LiveDashboard panels for operational visibility.

- User count by tier
- Island count / poll success rate
- Alert volume over time
- API error rate / circuit breaker status

---

## 4. Data & API Changes

### New DB Migration (Phase 2)

One migration to support dead island state machine:

```elixir
defmodule IslandPulse.Repo.Migrations.AddIslandStatusAndNullPollCount do
  use Ecto.Migration

  def change do
    alter table(:islands) do
      add :null_poll_count, :integer, default: 0, null: false
      add :status, :string, size: 20, default: "active", null: false
    end

    create index(:islands, [:status])
  end
end
```

### New API Endpoints (Phase 4)

No new external APIs needed. The web dashboard uses the same context functions as the Telegram bot.

### New Oban Jobs (Phase 2)

- `DeadIslandCheckJob` — runs weekly, checks dead islands for recovery

---

## 5. Testing Strategy

### Domain Tests (Priority 1)

| Module | What to Test |
|--------|-------------|
| `FortniteApi` | Parse normal response, parse empty data, circuit breaker open/close, rate limit handling |
| `AlertEngine` | Threshold eval at each maturity level, cooldown enforcement, EWMA escalation, dead island detection |
| `Metrics` | Median computation, EWMA computation, data maturity, cleanup bounds |
| `Islands` | Version change detection, user-island linking |

### Integration Tests (Priority 2)

| Flow | What to Verify |
|------|---------------|
| Full poll cycle | API fetch → parse → upsert → alert eval → CRITICAL delivery |
| Dead island flow | 3 null polls → dead status → weekly check-in → recovery |
| Bot command flow | /add → island linked → poll enqueued → data appears |

### Test Data

Use `start_supervised!([IslandPulse.Repo])` for isolated DB. Seed test islands with known metric values to make assertions deterministic.

---

## 6. Migration & Rollback Concerns

### Current State
- Single migration (`20260611092600_create_core_tables.exs`) — already run in dev/test
- No data loss risk from existing schema changes (nothing to roll back)

### Upcoming Migration (Phase 2)
- Adding `null_poll_count` and `status` to `islands` table is **non-destructive** (default values ensure no NULL violations)
- Rollback: simply drop the columns — existing data preserved

### Data Retention Risk
- Cleanup job deletes hour/minute metrics past retention — this is **irreversible** by design
- Day metrics are never deleted (forever retention per spec)
- If cleanup runs with wrong retention config, data is permanently lost — add logging of deleted count for auditability

---

## 7. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Fortnite API rate limits** | High | Polling fails, stale data | Circuit breaker already implemented; bounded concurrency (5); exponential backoff in retry logic |
| **Alert fatigue** | Medium | Users mute/disable alerts | Cooldown already enforced (24h for CRITICAL); escalation only on worsening metrics; configurable thresholds |
| **EWMA false positives** | Low-Medium | Unnecessary alerts on noisy data | EWMA only escalates when median baseline says "no change"; configurable decay factor |
| **Dead island false positive** | Medium | Alert sent for API outage, not dead island | Grace period (3 null polls); circuit breaker state checked before marking dead; weekly check-in confirms |
| **Oban job pileup** | Low | Backlog grows if API slow | Bounded concurrency; max_attempts=3 with exponential backoff; dead letter queue monitoring via LiveDashboard |
| **Circuit breaker :persistent_term** | Low | Single point of state; crashes reset it | Acceptable for MVP; consider ETS or GenServer-based breaker in V2 if reliability becomes critical |
| **Telegram Bot API downtime** | Low | Alerts not delivered | Retry with max_attempts=2 on DailySummaryJob; CRITICAL alerts sent immediately from PollIslandJob (shorter failure window) |

---

## 8. Dependency Graph (Issue Tracking)

```
[Phase 1 - Critical Wiring]
├── Wire alert eval into PollIslandJob (BLOCKS everything downstream)
│   ├── Add EWMA trend to alert engine
│   ├── Add health signal logic
│   └── Add prod Oban crontab
└── Domain unit tests (can start in parallel once alert wiring is merged)

[Phase 2 - Dead Island + Tests]
├── Dead island state machine (depends on alert wiring)
│   └── New migration: add null_poll_count + status to islands
├── Integration test for full pipeline (depends on alert wiring + dead island)
└── Bot command tests (independent — can start early)

[Phase 3 - Cleanup]
├── Remove unused deps (Tesla, Hackney) — independent
├── Version change detection integration (depends on alert wiring)
└── Cleanup job verification — independent
```

### Critical Path

```
Wire alert eval → Dead island state machine → Integration test
```

Everything else is parallelizable.

---

## 9. Open Questions

1. **Should CRITICAL alerts include a "snooze" option?** Currently no cooldown override for users — they get at most one CRITICAL per 24h per metric. Should we allow manual snoozing?
2. **Is the current dead island threshold (3 null polls) correct?** Fortnite API returns null when an island has <5 unique players — this could be a false positive for new/small islands.
3. **Should health signals be persisted?** Currently computed on-the-fly. Persisting would allow historical tracking but adds complexity.
4. **Quantum vs Oban crontab:** The app uses both Quantum (in application.ex) AND Oban crontab (in dev.exs). Are there duplicate jobs? Should we consolidate to one scheduler?

---

*Last updated: 2026-06-11 | Author: Island Pulse Team*
