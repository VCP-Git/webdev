# VCP Operations Platform — Project Documentation

## Overview

The Veterans Coaching Project (VCP) is a nonprofit that matches veteran clients with volunteer coaches through cohort-based coaching programs. This platform replaces a manual Google Forms + Google Sheets workflow with an integrated system built on Supabase, Cloudinary, Resend, and Squarespace.

**Project Owner:** Detan Ajala, IT Lead at VCP
**Website:** veteranscoachingproject.org (Squarespace)
**DNS:** GoDaddy
**Email:** Microsoft 365 / Outlook

---

## Tech Stack

| Service | Purpose | Details |
|---------|---------|---------|
| **Supabase** | Database + API | Project: `gerqcnkjhsloskhbmgil.supabase.co` |
| **Cloudinary** | Headshot image storage | Cloud name: `dzbzox0x8`, Upload preset: `vcp_headshots` |
| **Resend** | Transactional emails | Domain verified: `veteranscoachingproject.org`, Sends from: `engage@veteranscoachingproject.org` |
| **Squarespace** | Website / frontend host | Forms and dashboard embedded via Code Blocks |
| **Power BI** | Reporting | Connects to Supabase Postgres directly |
| **GoDaddy** | DNS management | Hosts DNS for veteranscoachingproject.org |

### API Keys & Config

- **Supabase Project URL:** `https://gerqcnkjhsloskhbmgil.supabase.co`
- **Supabase Anon Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdlcnFjbmtqaHNsb3NraGJtZ2lsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI5MDg0MzksImV4cCI6MjA4ODQ4NDQzOX0.DOfieo_KHHqBvoaiwFjysoAX6c49xc3zIv04BCUPCO4` (the newer `sb_publishable_` key returns 401 on REST API calls — always use this legacy anon key)
- **Supabase Service Role Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdlcnFjbmtqaHNsb3NraGJtZ2lsIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjkwODQzOSwiZXhwIjoyMDg4NDg0NDM5fQ.FvNnFMMBFgyJ0QLbmjoIYBLho5UcOipX8FmhRPv9MxM` (bypasses RLS — backend use only)
- **Cloudinary Cloud:** `dzbzox0x8`
- **Cloudinary Upload Preset:** `vcp_headshots` (unsigned, folder: `vcp_headshots`)
- **Resend API Key:** `re_7hYCPAuo_FrVeAzWzaxmEwNEXUXFYN2bH`
- **Resend Send-From:** `engage@veteranscoachingproject.org`
- **GitHub PAT:** `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` (repo scope, org: VCP-Git, repo: webdev)

### Brand

- **Colors:** `#343963` (navy), `#455560` (slate/teal), `#646C91` (periwinkle), `#FFFFFF` (white)
- **Fonts:** DM Sans (body), DM Serif Display (headings)

---

## Current State (Phase 2 Complete)

### Database Schema (LIVE)

Phase 2 relational schema is fully deployed with all data migrated from the v11 spreadsheet.

```
┌──────────────┐     ┌─────────────────────┐
│   people     │────<│ client_applications  │
│  (559+)      │     │  (272+)              │
│              │     └─────────────────────┘
│  legacy_id   │             │
│  (phone #)   │     ┌───────┴─────────────┐
│              │────<│ coach_applications   │
│              │     │  (549+)              │
│              │     └─────────────────────┘
│              │             │
└──────────────┘     ┌───────┴─────────────┐
                     │   new_matches        │
┌──────────────┐     │  (227+)              │
│   cohorts    │────<│  client_app_id       │
│  (16)        │     │  coach_app_id        │
│              │     │  status              │
└──────────────┘     └─────────────────────┘
```

#### `people` table — 559+ records
Single source of truth for every person in VCP. One row per human regardless of cohorts.

| Key Column | Notes |
|------------|-------|
| `legacy_id` | Phone number — the **reliable deduplication key** from the old spreadsheet. UNIQUE NOT NULL. |
| `vcp_id` | Auto-assigned: `VCP-C-XXXX` (clients) or `VCP-K-XXXX` (coaches) |
| `id_type` | `'client'`, `'coach'`, or `'both'` |
| `email` | NOT unique (19 people have different emails across cohorts) |
| `headshot_url` | Cloudinary URL — 472 photos migrated from Google Drive |

#### `client_applications` table — 272+ records
One row per client per cohort.

| Key Column | Notes |
|------------|-------|
| `person_id` + `cohort_id` | UNIQUE constraint — one application per person per cohort |
| `status` | CHECK: `Waitlisted`, `Active`, `Completed`, `Dropped`, `Coach Dropped`, `Extended`, `Deferred` |
| `priority` | TEXT column (not generated), calculated by `calc_client_priority()` |
| `assigned_category` | Admin-assigned: Career/Life/Business/Wellness/Executive Coaching |
| `waiver_signed` | Boolean + `waiver_signed_date` |

#### `coach_applications` table — 549+ records
One row per coach per cohort.

| Key Column | Notes |
|------------|-------|
| `coaching_specializations` | TEXT[] array |
| `status` | CHECK: `Waitlisted`, `Active`, `Completed`, `Dropped`, `Inactive`, `Extended` |
| `priority` | TEXT column, calculated by `calc_coach_priority()` |
| `max_clients` | Default 1 |

#### `new_matches` table — 227+ records
Links one coach to one client within a cohort.

| Key Column | Notes |
|------------|-------|
| `client_application_id` | UNIQUE — a client can only be matched once per cohort |
| `status` | `Active`, `Completed`, `Dropped - Client`, `Dropped - Coach`, `Dropped - Mutual`, `Reassigned` |

#### `cohorts` table — 16 cohorts
Spring 2021 through Summer 2026, with `cohort_numeric` field for ordering.

| Key Column | Notes |
|------------|-------|
| `cohort_name` | UNIQUE, e.g. "Spring 2026" |
| `cohort_numeric` | `year * 10 + season_index` for ordering |
| `status` | `Planning`, `Active`, `Completed`, `Archived` |
| `cohort_label` | e.g. "Cohort 14.0" — configurable in dashboard |
| Email config columns | ~17 columns for kickoff dates, meeting URLs, session schedules, etc. |

### Views

| View | Purpose |
|------|---------|
| `v_client_dashboard` | Joins client_applications + people + cohorts + new_matches + coach info |
| `v_coach_dashboard` | Joins coach_applications + people + cohorts + active match count |
| `v_person_history` | Cross-cohort history per person |
| `v_cohort_summary` | Per-cohort stats |

---

## Priority System

Priorities are calculated by `calc_client_priority()` and `calc_coach_priority()` functions, matching the original Google Apps Script logic exactly.

### Client Priority

| Priority | Condition |
|----------|-----------|
| **P1** | Waitlisted or coach-dropped in prior cohort (never got full experience — deserve first shot) |
| **P2** | Brand new applicant (no prior cohort history) |
| **P3** | Active, previously completed, or client-dropped voluntarily |
| **Unassigned** | Everything else |

### Coach Priority

| Priority | Condition |
|----------|-----------|
| **P1** | Waitlisted in the **immediately previous** cohort (cohort_numeric - 1) AND not previously participated |
| **P2** | No prior cohort rows (first appearance) |
| **P3** | Currently active OR has completed before |
| **Unassigned** | Everything else |

---

## Status Definitions

### Client Statuses

| Status | Meaning |
|--------|---------|
| **Waitlisted** | Default on application — in the queue, no coach yet |
| **Active** | Paired with a coach, coaching in progress |
| **Completed** | Finished the cohort |
| **Dropped** | Client left voluntarily |
| **Coach Dropped** | Coach left — not the client's fault |
| **Extended** | Still going, carried over |
| **Deferred** | Asked to move to next cohort |

**Note:** There is NO "Applied", "Reviewed", or "Matched" status. Everyone enters as Waitlisted. Being matched = Active.

### Coach Statuses

`Waitlisted`, `Active`, `Completed`, `Dropped`, `Inactive`, `Extended`

---

## Triggers & Automation

### Sync Trigger: `trg_sync_client` on `clients` table
**Purpose:** The intake form writes to the old `clients` table. This trigger copies new submissions into `people` + `client_applications`.

**Behavior:**
1. Finds or creates person in `people` by email (then legacy_id fallback)
2. Finds cohort by name match, falls back to active cohort, then planning cohort
3. Creates `client_application` with all rich fields mapped
4. Default status: `Waitlisted`
5. Calculates priority via `calc_client_priority()`
6. ON CONFLICT updates instead of duplicating

### Rollover System: Auto-carry waitlisted people to next cohort

**Trigger A — `trg_auto_rollover` on `cohorts` AFTER INSERT:**
When a new cohort is created, automatically pulls all Waitlisted clients and coaches from the previous cohort. Their priority recalculates (Waitlisted in Spring 2026 = P1 in Summer 2026).

**Trigger B — `trg_cleanup_client_rollover` on `client_applications` AFTER UPDATE:**
When a client's status changes to Active/Completed/Extended in their original cohort, their rollover entry in the next cohort is auto-deleted (if they're still Waitlisted there and not already matched).

**Same for coaches:** `trg_cleanup_coach_rollover` on `coach_applications`.

**Callable functions:**
- `rollover_clients('Spring 2026', 'Summer 2026')` — manual rollover
- `rollover_coaches('Spring 2026', 'Summer 2026')` — manual rollover
- `rollover_all('Spring 2026', 'Summer 2026')` — both at once
- `recalc_all_priorities()` — recalculates all client + coach priorities

### Match Email Trigger: `trg_send_match_emails` on `new_matches` AFTER INSERT
**Purpose:** Sends three emails via pg_net + Resend when a match is created:

1. **To the client** — "Congratulations! You've been matched with [Coach Name]" with cohort dates, meeting links, waiver reminders
2. **To the coach** — "You've been matched with [Veteran Client Name]" with agreements, kickoff details, forum/supervision dates
3. **To `engage@veteranscoachingproject.org`** — team notification with both names and match details

All dates, meeting URLs, and session schedules pull from the `cohorts` table email config columns.

### Intake Form Email Trigger: `send_intake_emails()` on `clients` AFTER INSERT
Sends client confirmation email + team notification email on new form submissions.

---

## Dashboard (vcp-dashboard-v4.html)

Self-contained HTML file, embeds in Squarespace. Uses `width:100vw; margin-left:calc(-50vw + 50%)` for full-width.

### Three Views

| View | Toggle Button | Purpose |
|------|---------------|---------|
| **👤 Clients** | Default | Client-centered matching workflow |
| **🎓 Coaches** | Toggle | Coach management + see who they're matched with |
| **⚙️ Cohorts** | Toggle | Configure cohort dates, meeting links, email settings |

### Clients View

**Layout:** Master-detail — client list left, detail + coach comparison right.

**Topbar:** Navy bar, cohort selector, stat pills (Total/Active/P1/P2/P3), "+ New Cohort" button.

**Tabs:** All / Unmatched / Has Coach

**Filters:** Status, Priority, Category, Waiver, Search — all combine with AND logic.

**Client Detail Panel:**
- Hero header with headshot (if available), name, ID, email, priority/category/status badges
- Match banner (if matched): coach name, match status
- Admin controls bar: Status dropdown, Category dropdown, Waiver toggle, Notes input, 🗑 Delete button
- Action buttons: 📄 Download PDF, 👤 View Profile
- Profile cards (solid white, clean borders, 15px text):
  - Bio + Goals side by side
  - Passions + Obstacles side by side
- Collapsible: Contact, Military & Coaching Details (2-col when expanded)
- Recommended Coaches section with search

**Compare Mode:** Click any coach card → panel splits into 2 columns (client left, coach right). Green "Match" button at top. Match confirmation popup mentions that emails will be sent.

### Coaches View

Same master-detail layout but for coaches. Includes:
- Coach list with specializations, match count, priority
- Tabs: All / Unmatched / Has Clients / Waitlisted / Active
- Full coach detail: admin bar, matched clients list, bio, matching notes, inspiration, hobbies
- All admin actions: status edit, category, notes, delete

### Cohorts Management View

Full cohort configuration with proper form controls:

| Field | Control Type |
|-------|-------------|
| Cohort Number | Dropdown (1.0 – 50.0), auto-prepends "Cohort" |
| Status | Dropdown: Planning/Active/Completed/Archived |
| All dates | Native date pickers |
| All times | Dropdowns: Hour (1-12) : Minutes (00/15/30/45) AM/PM Timezone |
| Meeting URLs | Text input for paste |
| Replay URLs | Text input for paste |
| Session dates | Interactive session builder — date picker + time + Zoom link per session, "+ Add Session" button, ✕ to remove |

**Sections:**
- Basic Info (cohort number, status)
- Kickoff Meeting (date, time, Zoom URL, replay URL)
- Client Introduction Meeting (date, time, meeting URL, replay URL) — side by side with Coach Intro
- Coach Introduction Meeting (date, time, meeting URL, replay URL)
- Group Coaching Sessions (dynamic session builder, full width)
- Coaching Forum + Coaching Supervision (side by side, dynamic session builders)
- Additional Email Notes (textarea)

**Behavior:**
- All fields save immediately on blur/change — no save button
- All fields are optional — fill in as dates are decided
- Setting status to Active auto-demotes the current active cohort to Completed
- Creating a new cohort triggers auto-rollover of waitlisted clients/coaches

### PDF Profile Download

**📄 Download PDF** and **👤 View Profile** buttons appear on both client and coach detail panels.

Opens a new window with a formatted profile page:
- Navy header (or slate for coaches) with headshot, name, email, ID, priority/category/status badges
- Card layout: Bio + Goals (or Bio + Matching Notes for coaches) side by side
- Detail grid: Contact, military, coaching info
- VCP branded footer with date
- "Print / Save as PDF" button (hidden when printing via `@media print`)

### Delete Actions

🗑 Delete button in admin bar for both clients and coaches. Double confirmation required.

**Smart cleanup:**
1. Deletes match records first (foreign key)
2. Deletes the application from this cohort
3. If person has NO other applications in any cohort — deletes person record entirely + old table entry
4. If person HAS other cohort applications — only removes from this cohort

---

## Client Intake Form (vcp-intake-form-dynamic.html)

Multi-step interactive HTML form embedded in Squarespace. 1,363 lines.

**6 Steps:** Basics → Location → Military Service → Coaching Goals → About You → Finish

**Dynamic Cohort:** On page load, queries `cohorts` table for Active cohort (falls back to Planning). Badge updates automatically. Form submits with the current cohort name.

**Submission Flow:**
1. Upload headshot to Cloudinary
2. Submit to Supabase `clients` table via REST API
3. Sync trigger copies to `people` + `client_applications`
4. Intake email trigger sends confirmation + team notification

**Squarespace notes:**
- CSS scoped under `.vcp-form-wrapper`
- Font sizes/padding bumped ~15% for Squarespace container shrinkage
- Full-width breakout: `width:100vw; margin-left:calc(-50vw + 50%)`

---

## Photo Migration

472 of 519 headshots migrated from Google Drive to Cloudinary.

**Script:** `vcp_photo_migration.py` + `photo_manifest.json`
- Downloads from Google Drive by file ID
- Uploads to Cloudinary (`vcp_headshots` folder)
- Updates `people.headshot_url` in Supabase
- Skips people who already have a Cloudinary headshot

**Results:**
- 472 successfully migrated
- 9 skipped (already had headshots from intake form)
- 38 failed (12 HTTP 404 — deleted files, 8 Cloudinary upload failures, others not publicly shared)

---

## Data Migration

### Source: `VCP_Operations__DATA___11_.xlsx`

| Tab | Records | Purpose |
|-----|---------|---------|
| Masterlist Clients | 257 | Match/status/priority data by cohort |
| Masterlist Coaches | 507 | Match/status/priority data by cohort |
| ALL FIELDS CLIENTS NEW | 149+ | Full intake form data (bios, headshots) |
| ALL FIELDS COACHES NEW | 225+ | Full coach application data |

### Migration Files (run in order)

| File | Purpose |
|------|---------|
| `resync_part1_setup_people.sql` | Clears data, sets constraints, inserts 559 people |
| `resync_part2_clients.sql` | 257 client applications |
| `resync_part3_coaches.sql` | 507 coach applications |
| `resync_part4_matches_fixup.sql` | 283 matches, priority recalc, form submission re-sync |
| `fix_missing_matches.sql` | 42 additional matches (coaches missing from Coaches Masterlist for their matched cohort) |

### Key Migration Decisions

- **Phone number is the reliable ID** — `legacy_id` = phone number (10 digits). Coaches appear inconsistently across cohort tabs; phone resolves deduplication.
- **42 missing coach applications** — coaches matched to clients but absent from the Coaches Masterlist for that specific cohort. Auto-created coach applications to link the matches.
- **`_pm` temp table** — must be a REAL table (not TEMP) since Supabase SQL Editor runs each query in separate session.
- **"Coach Dropped" and "Client Dropped"** in Coaches Masterlist both map to "Dropped" for the coach's own record. The distinction is preserved only in `new_matches.status`.

### Verified Cohort Data

```
Fall 2021:    11 clients,   5 coaches,   0 matches
Spring 2021:  10 clients,   9 coaches,   8 matches
Spring 2022:   7 clients,   9 coaches,   7 matches
Fall 2022:     9 clients,   9 coaches,   9 matches
Summer 2022:  12 clients,  11 coaches,  11 matches
Spring 2023:  11 clients,  27 coaches,   9 matches
Summer 2023:   7 clients,  17 coaches,   4 matches
Fall 2023:    16 clients,  20 coaches,  16 matches
Spring 2024:  15 clients,  26 coaches,   8 matches
Summer 2024:  16 clients,  40 coaches,  14 matches
Fall 2024:    32 clients,  64 coaches,  32 matches
Spring 2025:  35 clients, 100 coaches,  35 matches
Summer 2025:  35 clients, 120 coaches,  33 matches
Spring 2026:  49 clients,  85 coaches,  41 matches
Summer 2026:   9 clients,   0 coaches,   0 matches (rollover + form)
```

---

## Automated Email System

### Intake Confirmation (LIVE)
- **Trigger:** `send_intake_emails()` on `clients` AFTER INSERT
- **To client:** Welcome email with application summary
- **To team:** New Client Application notification with full details
- **Via:** pg_net + Resend API

### Match Confirmation (LIVE)
- **Trigger:** `send_match_emails()` on `new_matches` AFTER INSERT
- **To client:** "You've been matched with [Coach Name]" + cohort dates, waiver reminders, group coaching schedule
- **To coach:** "You've been matched with [Client Name]" + agreement instructions, kickoff details, forum/supervision dates
- **To team:** Match notification with both names and category
- **All dates/links pull from cohorts table** — configured via ⚙️ Cohorts dashboard view

### Cohort Email Config Columns (on `cohorts` table)

| Column | Purpose |
|--------|---------|
| `cohort_label` | e.g. "Cohort 14.0" |
| `kickoff_date`, `kickoff_time` | Kickoff meeting datetime |
| `kickoff_zoom_url`, `kickoff_replay_url` | Meeting + replay links |
| `client_intro_date`, `client_intro_time` | Client intro meeting |
| `client_intro_url`, `client_intro_replay_url` | Meeting + replay links |
| `coach_intro_date`, `coach_intro_time` | Coach intro meeting |
| `coach_intro_url`, `coach_intro_replay_url` | Meeting + replay links |
| `group_coaching_dates` | Newline-separated, parsed for client emails |
| `coaching_forum_dates` | Newline-separated, parsed for coach emails |
| `coaching_supervision_dates` | Newline-separated, parsed for coach emails |
| `email_notes` | Extra info for emails |

---

## Source Files Reference

| File | Purpose |
|------|---------|
| `vcp-dashboard-v4.html` | Main dashboard — clients, coaches, cohorts views |
| `vcp-intake-form-dynamic.html` | Client intake form with dynamic cohort |
| `vcp_match_emails.sql` | Match email trigger + cohort config columns |
| `vcp_rollover.sql` | Rollover functions + cleanup triggers |
| `vcp_auto_rollover.sql` | Auto-rollover trigger on cohort creation |
| `vcp_fix_statuses.sql` | Status corrections, sync trigger update |
| `vcp_client_sync_trigger.sql` | Sync trigger: clients → people + client_applications |
| `vcp_photo_migration.py` | Script to migrate Google Drive photos to Cloudinary |
| `photo_manifest.json` | Email → Google Drive file ID mapping (519 entries) |
| `resync_part1-4.sql` | Full data resync from v11 spreadsheet |
| `fix_missing_matches.sql` | 42 missing matches fix |
| `VCP_Operations__DATA___11_.xlsx` | Current source spreadsheet |

---

## Security Notes

- **RLS is DISABLED** on all tables. The anon key is used directly from the dashboard and intake form.
- **Long-term fix:** Supabase Edge Function proxy using `service_role` key server-side.
- **Resend API key** is embedded in the database trigger function (pg_net calls). Not exposed to the frontend.
- **Supabase Anon Key** is in the frontend code — this is expected for Supabase's security model, but RLS should be enabled before production.

---

## Known Issues & Technical Debt

1. **RLS disabled** — needs Edge Function proxy for proper security
2. **Coach intake form** — not yet built; coaches still apply via Google Form
3. **38 failed photo migrations** — 12 are deleted Drive files, rest need manual attention
4. **Power BI connection** — not yet set up
5. **Squarespace embed of dashboard** — works but needs testing in live environment
6. **Session Zoom links in emails** — stored in session data but email trigger doesn't yet parse them per-session (sends as text block)
7. **Replay URL triggers** — future: filling in a replay URL could trigger email to all cohort participants
8. **PDF attachments in emails** — currently emails mention "attached profile" but don't actually attach PDFs (would need Resend attachment API)

---

## Development Approach

- **Surgical edits preferred** over full rewrites when modifying existing files
- **Proper form controls expected** — date pickers, time selectors, dropdowns are assumed, not optional
- **Squarespace compatibility** is paramount — no `backdrop-filter`, all CSS must work without advanced features
- **VCP terminology must match existing workflow** — don't add new statuses without approval. Valid client statuses: Waitlisted, Active, Completed, Dropped, Coach Dropped, Extended, Deferred.
- **Phone number is the reliable coach ID** — coaches appear inconsistently across cohort tabs; phone number resolves deduplication
- **Stay close to existing VCP terminology** until after the CEO demo, then iterate
- **Test from published pages** in incognito mode, not the Squarespace editor
- **Use legacy anon JWT key** for Supabase REST API calls
- **SQL Editor quirks:** `id` column must be set as Primary with type `int8` before CSV import. Auto-increment requires manual `CREATE SEQUENCE` + `setval`. SQL editor mangles long inline HTML strings.
- **No `backdrop-filter`** — doesn't render in Squarespace. Use solid cards with borders and shadows instead.
