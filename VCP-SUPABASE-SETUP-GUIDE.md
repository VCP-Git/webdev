# VCP Supabase Database Setup Guide

## Purpose

This document contains every SQL query needed to set up the VCP Supabase database from scratch using the VCP Operations spreadsheet. It also includes the Python migration script that reads the XLSX file and generates SQL INSERT statements.

**Use this with Claude Code** to re-run migrations with updated spreadsheet data while preserving the exact same database structure.

---

## Prerequisites

- Supabase project: `https://gerqcnkjhsloskhbmgil.supabase.co`
- Supabase Anon Key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdlcnFjbmtqaHNsb3NraGJtZ2lsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI5MDg0MzksImV4cCI6MjA4ODQ4NDQzOX0.DOfieo_KHHqBvoaiwFjysoAX6c49xc3zIv04BCUPCO4`
- Resend API Key: `re_7hYCPAuo_FrVeAzWzaxmEwNEXUXFYN2bH`
- Source spreadsheet: `VCP_Operations__DATA___11_.xlsx` (or newer)
- Python 3 with `openpyxl` installed (`pip install openpyxl`)

---

## Execution Order

Run these in order. Each section is a separate SQL file to paste into Supabase SQL Editor.

1. **Step 1:** Schema (tables, indexes)
2. **Step 2:** Priority functions
3. **Step 3:** Views
4. **Step 4:** Triggers (auto-ID, timestamps, sync, rollover, match emails)
5. **Step 5:** Cohort email config columns
6. **Step 6:** Data migration (Python script generates SQL → paste into SQL Editor in 4 parts)

---

## Step 1: Schema

```sql
-- ============================================================================
-- VCP PHASE 2: RELATIONAL SCHEMA
-- Run in Supabase SQL Editor
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_net";

-- ── 1. COHORTS ──
CREATE TABLE IF NOT EXISTS cohorts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cohort_name   TEXT NOT NULL UNIQUE,
  season        TEXT NOT NULL CHECK (season IN ('Spring','Summer','Fall','Winter')),
  year          INT  NOT NULL,
  cohort_numeric INT UNIQUE,
  start_date    DATE,
  end_date      DATE,
  status        TEXT NOT NULL DEFAULT 'Planning'
                  CHECK (status IN ('Planning','Active','Completed','Archived')),
  notes         TEXT,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);

INSERT INTO cohorts (cohort_name, season, year, cohort_numeric, status) VALUES
  ('Spring 2021', 'Spring', 2021, 20211, 'Completed'),
  ('Fall 2021',   'Fall',   2021, 20213, 'Completed'),
  ('Spring 2022', 'Spring', 2022, 20221, 'Completed'),
  ('Summer 2022', 'Summer', 2022, 20222, 'Completed'),
  ('Fall 2022',   'Fall',   2022, 20223, 'Completed'),
  ('Spring 2023', 'Spring', 2023, 20231, 'Completed'),
  ('Summer 2023', 'Summer', 2023, 20232, 'Completed'),
  ('Fall 2023',   'Fall',   2023, 20233, 'Completed'),
  ('Spring 2024', 'Spring', 2024, 20241, 'Completed'),
  ('Summer 2024', 'Summer', 2024, 20242, 'Completed'),
  ('Fall 2024',   'Fall',   2024, 20243, 'Completed'),
  ('Spring 2025', 'Spring', 2025, 20251, 'Completed'),
  ('Summer 2025', 'Summer', 2025, 20252, 'Completed'),
  ('Spring 2026', 'Spring', 2026, 20261, 'Active'),
  ('Summer 2026', 'Summer', 2026, 20262, 'Planning')
ON CONFLICT (cohort_name) DO NOTHING;


-- ── 2. PEOPLE ──
CREATE TABLE IF NOT EXISTS people (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  vcp_id          TEXT UNIQUE,
  legacy_id       TEXT UNIQUE NOT NULL,        -- phone number = deduplication key
  id_type         TEXT CHECK (id_type IN ('client','coach','both')),
  first_name      TEXT NOT NULL,
  last_name       TEXT NOT NULL,
  preferred_name  TEXT,
  email           TEXT,                        -- NOT unique (19 people have diff emails across cohorts)
  phone           TEXT,
  city            TEXT,
  state           TEXT,
  country         TEXT DEFAULT 'US',
  zip             TEXT,
  is_veteran           BOOLEAN DEFAULT FALSE,
  military_status      TEXT,
  branch_of_service    TEXT,
  service_start_date   DATE,
  service_end_date     DATE,
  coaching_credentials TEXT,
  education_level      TEXT,
  professional_background TEXT,
  linkedin_url         TEXT,
  military_connection  TEXT,
  headshot_url    TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_people_email ON people(email);
CREATE INDEX IF NOT EXISTS idx_people_vcp_id ON people(vcp_id);
CREATE INDEX IF NOT EXISTS idx_people_legacy_id ON people(legacy_id);
CREATE INDEX IF NOT EXISTS idx_people_name ON people(last_name, first_name);


-- ── 3. CLIENT_APPLICATIONS ──
CREATE TABLE IF NOT EXISTS client_applications (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  person_id       UUID NOT NULL REFERENCES people(id) ON DELETE CASCADE,
  cohort_id       UUID NOT NULL REFERENCES cohorts(id),
  coaching_goals          TEXT,
  coaching_type_interest  TEXT,
  assigned_category       TEXT,
  availability            TEXT,
  preferred_meeting_format TEXT,
  bio                     TEXT,
  hobbies_interests       TEXT,
  referral_source         TEXT,
  referral_person         TEXT,
  emergency_contact_name  TEXT,
  emergency_contact_phone TEXT,
  emergency_contact_relation TEXT,
  waiver_signed           BOOLEAN DEFAULT FALSE,
  waiver_signed_date      DATE,
  participated_before     BOOLEAN DEFAULT FALSE,
  status          TEXT NOT NULL DEFAULT 'Waitlisted'
                    CHECK (status IN (
                      'Waitlisted','Active','Completed','Dropped',
                      'Coach Dropped','Extended','Deferred'
                    )),
  status_date     DATE DEFAULT CURRENT_DATE,
  status_notes    TEXT,
  is_returning    BOOLEAN DEFAULT FALSE,
  times_matched   INT DEFAULT 0,
  priority        TEXT DEFAULT 'Unassigned',
  applied_at      TIMESTAMPTZ DEFAULT now(),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(person_id, cohort_id)
);

CREATE INDEX IF NOT EXISTS idx_client_apps_cohort ON client_applications(cohort_id);
CREATE INDEX IF NOT EXISTS idx_client_apps_status ON client_applications(status);
CREATE INDEX IF NOT EXISTS idx_client_apps_priority ON client_applications(priority);
CREATE INDEX IF NOT EXISTS idx_client_apps_person ON client_applications(person_id);


-- ── 4. COACH_APPLICATIONS ──
CREATE TABLE IF NOT EXISTS coach_applications (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  person_id       UUID NOT NULL REFERENCES people(id) ON DELETE CASCADE,
  cohort_id       UUID NOT NULL REFERENCES cohorts(id),
  coaching_specializations TEXT[],
  coaching_areas_text      TEXT,
  assigned_category        TEXT,
  certifications           TEXT,
  max_clients              INT DEFAULT 1,
  availability_json        JSONB,
  bio                      TEXT,
  hobbies_interests        TEXT,
  affiliation              TEXT,
  coach_profile_url        TEXT,
  status          TEXT NOT NULL DEFAULT 'Waitlisted'
                    CHECK (status IN (
                      'Waitlisted','Active','Completed','Dropped',
                      'Inactive','Extended'
                    )),
  status_date     DATE DEFAULT CURRENT_DATE,
  status_notes    TEXT,
  is_returning    BOOLEAN DEFAULT FALSE,
  times_matched   INT DEFAULT 0,
  priority        TEXT DEFAULT 'Unassigned',
  applied_at      TIMESTAMPTZ DEFAULT now(),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(person_id, cohort_id)
);

CREATE INDEX IF NOT EXISTS idx_coach_apps_cohort ON coach_applications(cohort_id);
CREATE INDEX IF NOT EXISTS idx_coach_apps_status ON coach_applications(status);
CREATE INDEX IF NOT EXISTS idx_coach_apps_person ON coach_applications(person_id);


-- ── 5. NEW_MATCHES ──
CREATE TABLE IF NOT EXISTS new_matches (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cohort_id             UUID NOT NULL REFERENCES cohorts(id),
  coach_application_id  UUID NOT NULL REFERENCES coach_applications(id),
  client_application_id UUID NOT NULL REFERENCES client_applications(id),
  match_date            DATE DEFAULT CURRENT_DATE,
  matched_by            TEXT,
  status                TEXT NOT NULL DEFAULT 'Active'
                          CHECK (status IN (
                            'Active','Completed',
                            'Dropped - Client','Dropped - Coach','Dropped - Mutual',
                            'Reassigned'
                          )),
  status_date           DATE DEFAULT CURRENT_DATE,
  status_notes          TEXT,
  sessions_completed    INT DEFAULT 0,
  completion_date       DATE,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(client_application_id)
);

CREATE INDEX IF NOT EXISTS idx_new_matches_cohort ON new_matches(cohort_id);
CREATE INDEX IF NOT EXISTS idx_new_matches_coach ON new_matches(coach_application_id);
CREATE INDEX IF NOT EXISTS idx_new_matches_client ON new_matches(client_application_id);
```

---

## Step 2: Priority Functions

```sql
-- ============================================================================
-- PRIORITY CALCULATION FUNCTIONS
-- These match the Google Apps Script logic exactly
-- ============================================================================

-- ── CLIENT PRIORITY ──
-- P1 = waitlisted or coach-dropped in prior cohort
-- P2 = brand new applicant
-- P3 = active, previously completed, or client-dropped
CREATE OR REPLACE FUNCTION calc_client_priority(
  p_person_id UUID,
  p_cohort_id UUID
) RETURNS TEXT AS $$
DECLARE
  v_current_status TEXT;
  v_prev_completion BOOLEAN;
  v_current_numeric INT;
  v_prev_status TEXT;
  v_prior_count INT;
BEGIN
  SELECT cohort_numeric INTO v_current_numeric
  FROM cohorts WHERE id = p_cohort_id;

  SELECT ca.status, ca.is_returning INTO v_current_status, v_prev_completion
  FROM client_applications ca
  WHERE ca.person_id = p_person_id AND ca.cohort_id = p_cohort_id;

  -- Previously completed → P3
  IF v_prev_completion = TRUE THEN
    IF EXISTS (
      SELECT 1 FROM client_applications ca2
      JOIN cohorts c2 ON c2.id = ca2.cohort_id
      WHERE ca2.person_id = p_person_id
      AND c2.cohort_numeric < v_current_numeric
      AND ca2.status = 'Completed'
    ) THEN
      RETURN 'Priority 3';
    END IF;
  END IF;

  -- Currently Active → P3
  IF v_current_status = 'Active' THEN
    RETURN 'Priority 3';
  END IF;

  -- Most recent prior cohort: waitlisted or dropped → P1
  SELECT ca2.status INTO v_prev_status
  FROM client_applications ca2
  JOIN cohorts c2 ON c2.id = ca2.cohort_id
  WHERE ca2.person_id = p_person_id
  AND c2.cohort_numeric < v_current_numeric
  ORDER BY c2.cohort_numeric DESC
  LIMIT 1;

  IF v_prev_status IN ('Waitlisted', 'Dropped') THEN
    RETURN 'Priority 1';
  END IF;

  -- Check if match was dropped by coach → P1
  IF v_prev_status IN ('Active') THEN
    IF EXISTS (
      SELECT 1 FROM new_matches m
      JOIN client_applications ca3 ON ca3.id = m.client_application_id
      JOIN cohorts c3 ON c3.id = ca3.cohort_id
      WHERE ca3.person_id = p_person_id
      AND c3.cohort_numeric = (
        SELECT MAX(c4.cohort_numeric) FROM client_applications ca4
        JOIN cohorts c4 ON c4.id = ca4.cohort_id
        WHERE ca4.person_id = p_person_id AND c4.cohort_numeric < v_current_numeric
      )
      AND m.status = 'Dropped - Coach'
    ) THEN
      RETURN 'Priority 1';
    END IF;
  END IF;

  -- No prior cohorts → P2 (brand new)
  SELECT COUNT(*) INTO v_prior_count
  FROM client_applications ca2
  JOIN cohorts c2 ON c2.id = ca2.cohort_id
  WHERE ca2.person_id = p_person_id
  AND c2.cohort_numeric < v_current_numeric;

  IF v_prior_count = 0 THEN
    RETURN 'Priority 2';
  END IF;

  RETURN 'Unassigned';
END;
$$ LANGUAGE plpgsql STABLE;


-- ── COACH PRIORITY ──
-- P1 = waitlisted in immediately previous cohort AND has never coached (Active/Completed/Extended in any prior cohort)
-- P2 = no prior cohort rows (first appearance)
-- P3 = currently active OR has completed/been active before
-- NOTE: Uses actual coaching history, NOT is_returning flag (which gets set TRUE on all rollovers)
CREATE OR REPLACE FUNCTION calc_coach_priority(
  p_person_id UUID,
  p_cohort_id UUID
) RETURNS TEXT AS $$
DECLARE
  v_current_status TEXT;
  v_current_numeric INT;
  v_prev_numeric INT;
  v_prev_status TEXT;
  v_prior_count INT;
  v_ever_coached BOOLEAN;
  v_completed_before BOOLEAN;
BEGIN
  SELECT cohort_numeric INTO v_current_numeric
  FROM cohorts WHERE id = p_cohort_id;

  SELECT ka.status INTO v_current_status
  FROM coach_applications ka
  WHERE ka.person_id = p_person_id AND ka.cohort_id = p_cohort_id;

  -- Currently Active → P3
  IF v_current_status = 'Active' THEN
    RETURN 'Priority 3';
  END IF;

  -- Has ever actually coached (Active/Completed/Extended in any prior cohort)
  SELECT EXISTS(
    SELECT 1 FROM coach_applications ka2
    JOIN cohorts c2 ON c2.id = ka2.cohort_id
    WHERE ka2.person_id = p_person_id
    AND c2.cohort_numeric < v_current_numeric
    AND ka2.status IN ('Active', 'Completed', 'Extended')
  ) INTO v_ever_coached;

  -- Waitlisted in immediately previous cohort AND never coached before → P1
  v_prev_numeric := v_current_numeric - 1;
  SELECT ka2.status INTO v_prev_status
  FROM coach_applications ka2
  JOIN cohorts c2 ON c2.id = ka2.cohort_id
  WHERE ka2.person_id = p_person_id
  AND c2.cohort_numeric = v_prev_numeric;

  IF v_prev_status = 'Waitlisted' AND NOT v_ever_coached THEN
    RETURN 'Priority 1';
  END IF;

  -- No prior cohort rows → P2 (brand new)
  SELECT COUNT(*) INTO v_prior_count
  FROM coach_applications ka2
  JOIN cohorts c2 ON c2.id = ka2.cohort_id
  WHERE ka2.person_id = p_person_id
  AND c2.cohort_numeric < v_current_numeric;

  IF v_prior_count = 0 THEN
    RETURN 'Priority 2';
  END IF;

  -- Has completed before → P3
  SELECT EXISTS(
    SELECT 1 FROM coach_applications ka2
    JOIN cohorts c2 ON c2.id = ka2.cohort_id
    WHERE ka2.person_id = p_person_id
    AND c2.cohort_numeric < v_current_numeric
    AND ka2.status = 'Completed'
  ) INTO v_completed_before;

  IF v_completed_before THEN
    RETURN 'Priority 3';
  END IF;

  RETURN 'Unassigned';
END;
$$ LANGUAGE plpgsql STABLE;


-- ── CONVENIENCE FUNCTION ──
CREATE OR REPLACE FUNCTION recalc_all_priorities()
RETURNS void AS $$
BEGIN
  UPDATE client_applications ca
  SET priority = calc_client_priority(ca.person_id, ca.cohort_id);
  UPDATE coach_applications ka
  SET priority = calc_coach_priority(ka.person_id, ka.cohort_id);
END;
$$ LANGUAGE plpgsql;
```

---

## Step 3: Views

```sql
-- ============================================================================
-- DASHBOARD VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW v_client_dashboard AS
SELECT
  ca.id AS application_id,
  p.vcp_id AS client_id,
  p.legacy_id,
  p.first_name, p.last_name, p.preferred_name,
  p.email, p.phone, p.headshot_url,
  p.branch_of_service,
  c.cohort_name, c.id AS cohort_id,
  ca.coaching_type_interest, ca.assigned_category,
  ca.coaching_goals, ca.waiver_signed,
  ca.status, ca.status_date, ca.status_notes,
  ca.priority, ca.is_returning, ca.times_matched,
  ca.applied_at,
  m.id AS match_id, m.status AS match_status,
  coach_p.first_name AS coach_first_name,
  coach_p.last_name AS coach_last_name,
  coach_p.vcp_id AS coach_vcp_id
FROM client_applications ca
JOIN people p ON p.id = ca.person_id
JOIN cohorts c ON c.id = ca.cohort_id
LEFT JOIN new_matches m ON m.client_application_id = ca.id
LEFT JOIN coach_applications ka ON ka.id = m.coach_application_id
LEFT JOIN people coach_p ON coach_p.id = ka.person_id;


CREATE OR REPLACE VIEW v_coach_dashboard AS
SELECT
  ka.id AS application_id,
  p.vcp_id AS coach_id,
  p.legacy_id,
  p.first_name, p.last_name, p.email, p.phone, p.headshot_url,
  c.cohort_name, c.id AS cohort_id,
  ka.coaching_specializations, ka.assigned_category,
  ka.affiliation,
  ka.max_clients, ka.status, ka.status_date, ka.status_notes,
  ka.priority, ka.is_returning, ka.times_matched,
  ka.applied_at, ka.is_returning,
  (SELECT COUNT(*) FROM new_matches m
   WHERE m.coach_application_id = ka.id
   AND m.status = 'Active') AS active_match_count
FROM coach_applications ka
JOIN people p ON p.id = ka.person_id
JOIN cohorts c ON c.id = ka.cohort_id;


CREATE OR REPLACE VIEW v_person_history AS
SELECT
  p.id AS person_id, p.vcp_id, p.first_name, p.last_name, p.email,
  c.cohort_name, c.year, c.season,
  ca.status AS client_status, ca.priority AS client_priority, ca.assigned_category,
  ka.status AS coach_status,
  m_cl.status AS match_as_client_status,
  m_co.status AS match_as_coach_status
FROM people p
CROSS JOIN cohorts c
LEFT JOIN client_applications ca ON ca.person_id = p.id AND ca.cohort_id = c.id
LEFT JOIN coach_applications ka ON ka.person_id = p.id AND ka.cohort_id = c.id
LEFT JOIN new_matches m_cl ON m_cl.client_application_id = ca.id
LEFT JOIN new_matches m_co ON m_co.coach_application_id = ka.id
WHERE ca.id IS NOT NULL OR ka.id IS NOT NULL
ORDER BY p.last_name, c.year, c.season;


CREATE OR REPLACE VIEW v_cohort_summary AS
SELECT
  c.id AS cohort_id, c.cohort_name, c.status AS cohort_status,
  (SELECT COUNT(*) FROM client_applications x WHERE x.cohort_id = c.id) AS total_clients,
  (SELECT COUNT(*) FROM client_applications x WHERE x.cohort_id = c.id AND x.status = 'Active') AS active_clients,
  (SELECT COUNT(*) FROM client_applications x WHERE x.cohort_id = c.id AND x.status = 'Waitlisted') AS waitlisted_clients,
  (SELECT COUNT(*) FROM coach_applications x WHERE x.cohort_id = c.id) AS total_coaches,
  (SELECT COUNT(*) FROM new_matches x WHERE x.cohort_id = c.id) AS total_matches,
  (SELECT COUNT(*) FROM new_matches x WHERE x.cohort_id = c.id AND x.status = 'Completed') AS completed_matches
FROM cohorts c
ORDER BY c.year DESC, c.season;
```

---

## Step 4: Triggers

```sql
-- ============================================================================
-- ALL TRIGGERS
-- ============================================================================

-- ── AUTO-ID SEQUENCES ──
CREATE SEQUENCE IF NOT EXISTS client_id_seq START WITH 300;
CREATE SEQUENCE IF NOT EXISTS coach_id_seq START WITH 600;

CREATE OR REPLACE FUNCTION assign_vcp_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.vcp_id IS NULL THEN
    IF NEW.id_type = 'client' THEN
      NEW.vcp_id := 'VCP-C-' || LPAD(nextval('client_id_seq')::TEXT, 4, '0');
    ELSIF NEW.id_type = 'coach' THEN
      NEW.vcp_id := 'VCP-K-' || LPAD(nextval('coach_id_seq')::TEXT, 4, '0');
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_assign_vcp_id ON people;
CREATE TRIGGER trg_assign_vcp_id
BEFORE INSERT ON people
FOR EACH ROW EXECUTE FUNCTION assign_vcp_id();


-- ── UPDATED_AT TIMESTAMPS ──
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_people_ts ON people;
DROP TRIGGER IF EXISTS trg_cohorts_ts ON cohorts;
DROP TRIGGER IF EXISTS trg_client_apps_ts ON client_applications;
DROP TRIGGER IF EXISTS trg_coach_apps_ts ON coach_applications;
DROP TRIGGER IF EXISTS trg_matches_ts ON new_matches;

CREATE TRIGGER trg_people_ts      BEFORE UPDATE ON people              FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_cohorts_ts     BEFORE UPDATE ON cohorts             FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_client_apps_ts BEFORE UPDATE ON client_applications FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_coach_apps_ts  BEFORE UPDATE ON coach_applications  FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_matches_ts     BEFORE UPDATE ON new_matches         FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ── CLIENT SYNC TRIGGER (intake form → new schema) ──
CREATE OR REPLACE FUNCTION sync_client_to_new_tables()
RETURNS TRIGGER AS $$
DECLARE
  v_person_id UUID;
  v_cohort_id UUID;
  v_is_returning BOOLEAN;
BEGIN
  SELECT id INTO v_person_id FROM people WHERE email = LOWER(TRIM(NEW.email)) LIMIT 1;
  IF v_person_id IS NULL AND NEW.client_id IS NOT NULL THEN
    SELECT id INTO v_person_id FROM people WHERE legacy_id = NEW.client_id LIMIT 1;
  END IF;

  IF v_person_id IS NOT NULL THEN
    v_is_returning := TRUE;
    UPDATE people SET
      first_name = COALESCE(NULLIF(TRIM(NEW.first_name), ''), first_name),
      last_name = COALESCE(NULLIF(TRIM(NEW.last_name), ''), last_name),
      preferred_name = COALESCE(NULLIF(TRIM(NEW.preferred_name), ''), preferred_name),
      phone = COALESCE(NULLIF(TRIM(NEW.phone), ''), phone),
      city = COALESCE(NULLIF(TRIM(NEW.city), ''), city),
      state = COALESCE(NULLIF(TRIM(NEW.state), ''), state),
      country = COALESCE(NULLIF(TRIM(NEW.country), ''), country),
      zip = COALESCE(NULLIF(TRIM(NEW.zip), ''), zip),
      military_status = COALESCE(NULLIF(TRIM(NEW.military_status), ''), military_status),
      branch_of_service = COALESCE(NULLIF(TRIM(NEW.branch), ''), branch_of_service),
      headshot_url = COALESCE(NULLIF(TRIM(NEW.headshot_url), ''), headshot_url),
      is_veteran = TRUE, updated_at = now()
    WHERE id = v_person_id;
  ELSE
    v_is_returning := (LOWER(TRIM(COALESCE(NEW.previous_cohort, ''))) = 'yes');
    INSERT INTO people (legacy_id, id_type, first_name, last_name, preferred_name,
      email, phone, city, state, country, zip,
      is_veteran, military_status, branch_of_service, headshot_url)
    VALUES (NEW.client_id, 'client', TRIM(NEW.first_name), TRIM(NEW.last_name),
      NULLIF(TRIM(NEW.preferred_name), ''), LOWER(TRIM(NEW.email)),
      NULLIF(TRIM(NEW.phone), ''), NULLIF(TRIM(NEW.city), ''),
      NULLIF(TRIM(NEW.state), ''), NULLIF(TRIM(NEW.country), ''),
      NULLIF(TRIM(NEW.zip), ''), TRUE, NULLIF(TRIM(NEW.military_status), ''),
      NULLIF(TRIM(NEW.branch), ''), NULLIF(TRIM(NEW.headshot_url), ''))
    RETURNING id INTO v_person_id;
  END IF;

  SELECT id INTO v_cohort_id FROM cohorts WHERE LOWER(cohort_name) = LOWER(TRIM(COALESCE(NEW.cohort, ''))) LIMIT 1;
  IF v_cohort_id IS NULL THEN SELECT id INTO v_cohort_id FROM cohorts WHERE status = 'Active' ORDER BY year DESC, season DESC LIMIT 1; END IF;
  IF v_cohort_id IS NULL THEN SELECT id INTO v_cohort_id FROM cohorts WHERE status = 'Planning' ORDER BY year DESC, season DESC LIMIT 1; END IF;

  INSERT INTO client_applications (person_id, cohort_id, coaching_goals, coaching_type_interest,
    availability, bio, participated_before, is_returning, status, applied_at)
  VALUES (v_person_id, v_cohort_id, NULLIF(TRIM(NEW.accomplishments), ''),
    NULLIF(TRIM(NEW.coaching_types), ''), NULLIF(TRIM(NEW.availability), ''),
    NULLIF(TRIM(NEW.bio), ''), v_is_returning, v_is_returning,
    'Waitlisted', COALESCE(NEW.created_at, now()))
  ON CONFLICT (person_id, cohort_id) DO UPDATE SET
    coaching_goals = COALESCE(NULLIF(TRIM(NEW.accomplishments), ''), client_applications.coaching_goals),
    coaching_type_interest = COALESCE(NULLIF(TRIM(NEW.coaching_types), ''), client_applications.coaching_type_interest),
    availability = COALESCE(NULLIF(TRIM(NEW.availability), ''), client_applications.availability),
    bio = COALESCE(NULLIF(TRIM(NEW.bio), ''), client_applications.bio),
    updated_at = now();

  UPDATE client_applications SET priority = calc_client_priority(v_person_id, v_cohort_id)
  WHERE person_id = v_person_id AND cohort_id = v_cohort_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_client ON clients;
CREATE TRIGGER trg_sync_client AFTER INSERT ON clients FOR EACH ROW EXECUTE FUNCTION sync_client_to_new_tables();


-- ── ROLLOVER FUNCTIONS ──
CREATE OR REPLACE FUNCTION rollover_clients(p_from TEXT, p_to TEXT)
RETURNS TABLE(rolled_name TEXT, rolled_email TEXT, new_priority TEXT) AS $$
DECLARE v_from_id UUID; v_to_id UUID; v_person RECORD; v_new_priority TEXT;
BEGIN
  SELECT id INTO v_from_id FROM cohorts WHERE cohort_name = p_from;
  SELECT id INTO v_to_id FROM cohorts WHERE cohort_name = p_to;
  IF v_from_id IS NULL THEN RAISE EXCEPTION 'Source cohort "%" not found', p_from; END IF;
  IF v_to_id IS NULL THEN RAISE EXCEPTION 'Target cohort "%" not found', p_to; END IF;

  FOR v_person IN
    SELECT ca.person_id, ca.assigned_category, ca.coaching_goals,
           ca.coaching_type_interest, ca.availability, ca.bio,
           p.first_name, p.last_name, p.email
    FROM client_applications ca JOIN people p ON p.id = ca.person_id
    WHERE ca.cohort_id = v_from_id AND ca.status = 'Waitlisted'
  LOOP
    INSERT INTO client_applications (person_id, cohort_id, assigned_category, coaching_goals,
      coaching_type_interest, availability, bio, is_returning, participated_before, status, applied_at)
    VALUES (v_person.person_id, v_to_id, v_person.assigned_category, v_person.coaching_goals,
      v_person.coaching_type_interest, v_person.availability, v_person.bio, TRUE, TRUE, 'Waitlisted', now())
    ON CONFLICT (person_id, cohort_id) DO NOTHING;

    v_new_priority := calc_client_priority(v_person.person_id, v_to_id);
    UPDATE client_applications SET priority = v_new_priority
    WHERE person_id = v_person.person_id AND cohort_id = v_to_id;

    rolled_name := v_person.first_name || ' ' || v_person.last_name;
    rolled_email := v_person.email;
    new_priority := v_new_priority;
    RETURN NEXT;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rollover_coaches(p_from TEXT, p_to TEXT)
RETURNS TABLE(rolled_name TEXT, rolled_email TEXT, new_priority TEXT) AS $$
DECLARE v_from_id UUID; v_to_id UUID; v_person RECORD; v_new_priority TEXT;
BEGIN
  SELECT id INTO v_from_id FROM cohorts WHERE cohort_name = p_from;
  SELECT id INTO v_to_id FROM cohorts WHERE cohort_name = p_to;
  IF v_from_id IS NULL THEN RAISE EXCEPTION 'Source cohort "%" not found', p_from; END IF;
  IF v_to_id IS NULL THEN RAISE EXCEPTION 'Target cohort "%" not found', p_to; END IF;

  FOR v_person IN
    SELECT ka.person_id, ka.coaching_specializations, ka.assigned_category,
           ka.affiliation, ka.max_clients, p.first_name, p.last_name, p.email
    FROM coach_applications ka JOIN people p ON p.id = ka.person_id
    WHERE ka.cohort_id = v_from_id AND ka.status = 'Waitlisted'
  LOOP
    INSERT INTO coach_applications (person_id, cohort_id, coaching_specializations, assigned_category,
      affiliation, max_clients, is_returning, status, applied_at)
    VALUES (v_person.person_id, v_to_id, v_person.coaching_specializations, v_person.assigned_category,
      v_person.affiliation, v_person.max_clients, TRUE, 'Waitlisted', now())
    ON CONFLICT (person_id, cohort_id) DO NOTHING;

    v_new_priority := calc_coach_priority(v_person.person_id, v_to_id);
    UPDATE coach_applications SET priority = v_new_priority
    WHERE person_id = v_person.person_id AND cohort_id = v_to_id;

    rolled_name := v_person.first_name || ' ' || v_person.last_name;
    rolled_email := v_person.email;
    new_priority := v_new_priority;
    RETURN NEXT;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rollover_all(p_from TEXT, p_to TEXT) RETURNS TEXT AS $$
DECLARE v_cl INT; v_co INT;
BEGIN
  SELECT COUNT(*) INTO v_cl FROM rollover_clients(p_from, p_to);
  SELECT COUNT(*) INTO v_co FROM rollover_coaches(p_from, p_to);
  RETURN 'Rolled over ' || v_cl || ' clients and ' || v_co || ' coaches from ' || p_from || ' to ' || p_to;
END;
$$ LANGUAGE plpgsql;


-- ── AUTO-ROLLOVER ON COHORT CREATION ──
CREATE OR REPLACE FUNCTION auto_rollover_on_cohort_create()
RETURNS TRIGGER AS $$
DECLARE v_prev_name TEXT; v_prev_id UUID; v_cl INT := 0; v_co INT := 0;
BEGIN
  SELECT cohort_name, id INTO v_prev_name, v_prev_id FROM cohorts
  WHERE cohort_numeric < NEW.cohort_numeric ORDER BY cohort_numeric DESC LIMIT 1;
  IF v_prev_id IS NULL THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_cl FROM rollover_clients(v_prev_name, NEW.cohort_name);
  SELECT COUNT(*) INTO v_co FROM rollover_coaches(v_prev_name, NEW.cohort_name);
  RAISE NOTICE 'Auto-rollover: % clients and % coaches from % to %', v_cl, v_co, v_prev_name, NEW.cohort_name;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_rollover ON cohorts;
CREATE TRIGGER trg_auto_rollover AFTER INSERT ON cohorts FOR EACH ROW EXECUTE FUNCTION auto_rollover_on_cohort_create();


-- ── CLEANUP ROLLOVER ON STATUS CHANGE ──
CREATE OR REPLACE FUNCTION cleanup_rollover_on_status_change()
RETURNS TRIGGER AS $$
DECLARE v_current_numeric INT; v_next_cohort_id UUID;
BEGIN
  IF NEW.status NOT IN ('Active', 'Completed', 'Extended') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  SELECT cohort_numeric INTO v_current_numeric FROM cohorts WHERE id = NEW.cohort_id;
  SELECT id INTO v_next_cohort_id FROM cohorts WHERE cohort_numeric > v_current_numeric ORDER BY cohort_numeric ASC LIMIT 1;
  IF v_next_cohort_id IS NULL THEN RETURN NEW; END IF;
  DELETE FROM client_applications
  WHERE person_id = NEW.person_id AND cohort_id = v_next_cohort_id AND status = 'Waitlisted'
  AND NOT EXISTS (SELECT 1 FROM new_matches m WHERE m.client_application_id = client_applications.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cleanup_client_rollover ON client_applications;
CREATE TRIGGER trg_cleanup_client_rollover AFTER UPDATE OF status ON client_applications FOR EACH ROW EXECUTE FUNCTION cleanup_rollover_on_status_change();

CREATE OR REPLACE FUNCTION cleanup_coach_rollover_on_status_change()
RETURNS TRIGGER AS $$
DECLARE v_current_numeric INT; v_next_cohort_id UUID;
BEGIN
  IF NEW.status NOT IN ('Active', 'Completed', 'Extended') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  SELECT cohort_numeric INTO v_current_numeric FROM cohorts WHERE id = NEW.cohort_id;
  SELECT id INTO v_next_cohort_id FROM cohorts WHERE cohort_numeric > v_current_numeric ORDER BY cohort_numeric ASC LIMIT 1;
  IF v_next_cohort_id IS NULL THEN RETURN NEW; END IF;
  DELETE FROM coach_applications
  WHERE person_id = NEW.person_id AND cohort_id = v_next_cohort_id AND status = 'Waitlisted'
  AND NOT EXISTS (SELECT 1 FROM new_matches m WHERE m.coach_application_id = coach_applications.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cleanup_coach_rollover ON coach_applications;
CREATE TRIGGER trg_cleanup_coach_rollover AFTER UPDATE OF status ON coach_applications FOR EACH ROW EXECUTE FUNCTION cleanup_coach_rollover_on_status_change();
```

---

## Step 5: Cohort Email Config Columns

```sql
-- ============================================================================
-- COHORT EMAIL CONFIGURATION
-- Add columns for meeting dates, Zoom links, etc.
-- All are optional — fill in as dates are decided
-- ============================================================================

ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS cohort_label TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS kickoff_date TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS kickoff_time TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS kickoff_zoom_url TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS kickoff_replay_url TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS client_intro_date TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS client_intro_time TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS client_intro_url TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS client_intro_replay_url TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS coach_intro_date TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS coach_intro_time TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS coach_intro_url TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS coach_intro_replay_url TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS group_coaching_dates TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS coaching_forum_dates TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS coaching_supervision_dates TEXT;
ALTER TABLE cohorts ADD COLUMN IF NOT EXISTS email_notes TEXT;
```

---

## Step 6: Data Migration (Python Script)

Save this as `vcp_resync.py`. Run it against the spreadsheet to generate SQL INSERT statements, then paste the output into Supabase SQL Editor in 4 parts.

```python
"""
VCP Data Migration: XLSX → SQL
Reads the VCP Operations spreadsheet and generates SQL to populate Supabase.

Usage:
  python vcp_resync.py VCP_Operations__DATA___11_.xlsx > resync.sql

The output SQL should be split into 4 parts for Supabase SQL Editor
(which has a ~100KB paste limit per query):
  Part 1: Setup + People inserts
  Part 2: Client application inserts
  Part 3: Coach application inserts
  Part 4: Match inserts + priority recalc + verification

IMPORTANT: The script creates a helper table `_pm` (person map) to link
legacy_id → UUID across parts. This must be a REAL table (not TEMP) because
Supabase SQL Editor runs each query in a separate session.
"""

import openpyxl
import re
import sys
from collections import defaultdict

def esc(val):
    if val is None: return 'NULL'
    s = str(val).strip()
    if s == '' or s.lower() == 'none' or s == '#NAME?' or s == '#REF!': return 'NULL'
    s = s.replace("'", "''")
    return f"'{s}'"

def digits10(val):
    if val is None: return None
    s = re.sub(r'[^0-9]', '', str(val))[:10]
    return s if len(s) >= 7 else None

def norm_cohort(name):
    if not name: return None
    parts = str(name).strip().split()
    if len(parts) == 2: return f"{parts[0].capitalize()} {parts[1]}"
    return str(name).strip()

def map_client_status(desc):
    if not desc: return 'Waitlisted'
    s = str(desc).strip().lower()
    if s in ('active', 'a'): return 'Active'
    if s in ('completed', 'c'): return 'Completed'
    if s in ('dropped', 'd', 'client dropped'): return 'Dropped'
    if s in ('coach dropped', 'cd'): return 'Coach Dropped'
    if s in ('extended', 'e'): return 'Extended'
    if s in ('waitlisted', 'w', 'waitlist'): return 'Waitlisted'
    return 'Waitlisted'

def map_coach_status(desc):
    if not desc: return 'Waitlisted'
    s = str(desc).strip().lower()
    if s in ('active', 'a'): return 'Active'
    if s in ('completed', 'c'): return 'Completed'
    if 'dropped' in s: return 'Dropped'  # both coach/client dropped → Dropped for coach record
    if s in ('waitlisted', 'w', 'waitlist'): return 'Waitlisted'
    if s in ('inactive',): return 'Inactive'
    if s in ('extended', 'e'): return 'Extended'
    return 'Waitlisted'

def map_match_status(desc):
    s = str(desc).strip().lower() if desc else ''
    if 'completed' in s: return 'Completed'
    if 'client dropped' in s or 'client drop' in s: return 'Dropped - Client'
    if 'coach dropped' in s or 'coach drop' in s: return 'Dropped - Coach'
    if 'dropped' in s: return 'Dropped - Mutual'
    if 'active' in s: return 'Active'
    return 'Active'

def main():
    xlsx_path = sys.argv[1] if len(sys.argv) > 1 else 'VCP_Operations__DATA___11_.xlsx'
    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)

    def safe(vals, idx):
        if idx < len(vals) and vals[idx] and str(vals[idx]).strip().lower() not in ('none', '', 'n/a'):
            return str(vals[idx]).strip()
        return None

    # ── PARSE CLIENTS (Masterlist Clients tab) ──
    ws_cl = wb['Masterlist Clients']
    clients = []
    for row in ws_cl.iter_rows(min_row=2, values_only=True):
        vals = list(row)
        if not vals[0] or not str(vals[0]).strip(): continue
        client_id = digits10(vals[1])
        if not client_id: continue
        email = str(vals[5]).strip().rstrip(';').lower() if vals[5] and str(vals[5]).strip().lower() != 'none' else None

        clients.append({
            'cohort': norm_cohort(vals[0]),
            'id': client_id,
            'first': str(vals[3]).strip().title() if vals[3] else 'Unknown',
            'last': str(vals[4]).strip().title() if vals[4] else 'Unknown',
            'email': email,
            'phone': digits10(vals[7]),
            'branch': str(vals[8]).strip() if vals[8] and str(vals[8]).strip().lower() != 'none' else None,
            'cat': str(vals[2]).strip() if vals[2] and str(vals[2]).strip().lower() != 'none' else None,
            'waiver': str(vals[9]).strip().lower() == 'true' if vals[9] else False,
            'coach_phone': digits10(vals[13]),  # Matched Coach Phone = coach ID
            'status_desc': str(vals[17]).strip() if vals[17] and str(vals[17]).strip().lower() != 'none' else None,
            'notes': str(vals[15]).strip() if vals[15] and str(vals[15]).strip().lower() != 'none' else None,
            'prev': str(vals[20]).strip().lower() == 'yes' if len(vals) > 20 and vals[20] else False,
        })

    # ── PARSE COACHES (Masterlist Coaches tab) ──
    ws_co = wb['Masterlist Coaches']
    coaches = []
    for row in ws_co.iter_rows(min_row=2, values_only=True):
        vals = list(row)
        if not vals[0] or not str(vals[0]).strip(): continue
        coach_id = digits10(vals[4])
        if not coach_id: continue
        email = safe(vals, 7) if safe(vals, 7) else safe(vals, 10)
        if email: email = email.lower().rstrip(';')

        coaches.append({
            'cohort': norm_cohort(vals[0]),
            'id': coach_id,
            'first': str(vals[7]).strip().title() if vals[7] else (str(vals[2]).strip().title() if vals[2] else 'Unknown'),
            'last': str(vals[8]).strip().title() if vals[8] else (str(vals[3]).strip().title() if vals[3] else 'Unknown'),
            'email': email,
            'phone': digits10(vals[9]),
            'cat': safe(vals, 5),
            'spec': safe(vals, 6),
            'affiliation': safe(vals, 11),
            'profile': safe(vals, 12),
            'status_desc': safe(vals, 19),
            'notes': safe(vals, 22) if safe(vals, 22) and safe(vals, 22) != '.' else None,
            'prev': str(vals[2]).strip().lower() == 'yes' if vals[2] and str(vals[2]).strip().lower() not in ('none', '#ref!') else False,
        })

    # ── DEDUP PEOPLE ──
    people = {}
    for c in clients:
        if c['id'] not in people:
            people[c['id']] = {'id': c['id'], 'type': 'client', 'first': c['first'], 'last': c['last'],
                               'email': c['email'], 'phone': c['phone'], 'branch': c['branch'], 'vet': True}
        elif c['email'] and not people[c['id']].get('email'):
            people[c['id']]['email'] = c['email']

    for co in coaches:
        if co['id'] not in people:
            people[co['id']] = {'id': co['id'], 'type': 'coach', 'first': co['first'], 'last': co['last'],
                                'email': co['email'], 'phone': co['phone'], 'branch': None, 'vet': False}
        elif co['email'] and not people[co['id']].get('email'):
            people[co['id']]['email'] = co['email']

    # ── BUILD MATCHES using coach_phone as key ──
    # Also build set of (coach_id, cohort) from coaches tab
    coach_cohorts = set()
    for co in coaches:
        coach_cohorts.add((co['id'], co['cohort'].upper() if co['cohort'] else ''))

    match_set = {}
    for c in clients:
        if c['coach_phone'] and c['coach_phone'] in people:
            key = (c['cohort'].upper() if c['cohort'] else '', c['coach_phone'], c['id'])
            if key not in match_set:
                match_set[key] = {'cohort': c['cohort'], 'status': c['status_desc'], 'src': 'client'}

    print(f'-- Parsed {len(clients)} client rows, {len(coaches)} coach rows')
    print(f'-- {len(people)} unique people, {len(match_set)} matches')
    print()

    # ── GENERATE SQL ──
    print('-- ============================================================')
    print('-- VCP FULL DATA MIGRATION')
    print('-- ============================================================')
    print()
    print('-- Step 0: Clear existing data')
    print('DELETE FROM new_matches;')
    print('DELETE FROM client_applications;')
    print('DELETE FROM coach_applications;')
    print('DELETE FROM people;')
    print()
    print('DROP TABLE IF EXISTS _pm;')
    print('CREATE TABLE _pm (lid TEXT PRIMARY KEY, pid UUID);')
    print()

    # Insert people
    print('-- Step 1: Insert people')
    for lid, p in people.items():
        print(f"DO $$ DECLARE v UUID; BEGIN")
        print(f"  INSERT INTO people (legacy_id,id_type,first_name,last_name,email,phone,is_veteran,branch_of_service)")
        print(f"  VALUES ({esc(p['id'])},{esc(p['type'])},{esc(p['first'])},{esc(p['last'])},{esc(p['email'])},{esc(p['phone'])},{str(p['vet']).lower()},{esc(p['branch'])})")
        print(f"  ON CONFLICT (legacy_id) DO UPDATE SET updated_at=now()")
        print(f"  RETURNING id INTO v;")
        print(f"  INSERT INTO _pm VALUES ({esc(p['id'])},v) ON CONFLICT DO NOTHING;")
        print(f"END $$;")
        print()

    # Insert client applications
    print('-- Step 2: Insert client applications')
    for c in clients:
        status = map_client_status(c['status_desc'])
        print(f"INSERT INTO client_applications (person_id,cohort_id,assigned_category,waiver_signed,status,status_notes,is_returning,participated_before)")
        print(f"VALUES (")
        print(f"  (SELECT pid FROM _pm WHERE lid={esc(c['id'])}),")
        print(f"  (SELECT id FROM cohorts WHERE cohort_name={esc(c['cohort'])}),")
        print(f"  {esc(c['cat'])},{str(c['waiver']).lower()},{esc(status)},{esc(c['notes'])},")
        print(f"  {str(c['prev']).lower()},{str(c['prev']).lower()}")
        print(f") ON CONFLICT (person_id,cohort_id) DO NOTHING;")
        print()

    # Insert coach applications
    print('-- Step 3: Insert coach applications')
    for co in coaches:
        status = map_coach_status(co['status_desc'])
        specs = co['spec']
        if specs:
            items = [s.strip() for s in specs.split(',') if s.strip()]
            arr = "ARRAY[" + ",".join(esc(s) for s in items) + "]::TEXT[]"
        else:
            arr = "ARRAY[]::TEXT[]"
        print(f"INSERT INTO coach_applications (person_id,cohort_id,coaching_specializations,assigned_category,affiliation,coach_profile_url,status,status_notes,is_returning)")
        print(f"VALUES (")
        print(f"  (SELECT pid FROM _pm WHERE lid={esc(co['id'])}),")
        print(f"  (SELECT id FROM cohorts WHERE cohort_name={esc(co['cohort'])}),")
        print(f"  {arr},{esc(co['cat'])},{esc(co['affiliation'])},{esc(co['profile'])},")
        print(f"  {esc(status)},{esc(co['notes'])},{str(co['prev']).lower()}")
        print(f") ON CONFLICT (person_id,cohort_id) DO NOTHING;")
        print()

    # Auto-create missing coach applications (coaches matched but not in coaches tab for that cohort)
    print('-- Step 3b: Auto-create missing coach applications')
    for c in clients:
        if not c['coach_phone'] or c['coach_phone'] not in people: continue
        cohort_key = (c['coach_phone'], c['cohort'].upper() if c['cohort'] else '')
        if cohort_key not in coach_cohorts:
            print(f"INSERT INTO coach_applications (person_id,cohort_id,status,is_returning)")
            print(f"SELECT p.id,c.id,'Active',TRUE FROM people p, cohorts c")
            print(f"WHERE p.legacy_id={esc(c['coach_phone'])} AND c.cohort_name={esc(c['cohort'])}")
            print(f"AND NOT EXISTS (SELECT 1 FROM coach_applications ka WHERE ka.person_id=p.id AND ka.cohort_id=c.id)")
            print(f"ON CONFLICT (person_id,cohort_id) DO NOTHING;")
            print()

    # Insert matches
    print('-- Step 4: Insert matches')
    ok = 0
    for (coh_upper, coach_lid, client_lid), detail in match_set.items():
        if coach_lid not in people or client_lid not in people: continue
        mst = map_match_status(detail['status'])
        cn = detail['cohort']
        print(f"INSERT INTO new_matches (cohort_id,coach_application_id,client_application_id,status)")
        print(f"SELECT c.id,ka.id,ca.id,{esc(mst)}")
        print(f"FROM cohorts c")
        print(f"JOIN coach_applications ka ON ka.cohort_id=c.id AND ka.person_id=(SELECT pid FROM _pm WHERE lid={esc(coach_lid)})")
        print(f"JOIN client_applications ca ON ca.cohort_id=c.id AND ca.person_id=(SELECT pid FROM _pm WHERE lid={esc(client_lid)})")
        print(f"WHERE c.cohort_name={esc(cn)}")
        print(f"ON CONFLICT (client_application_id) DO NOTHING;")
        print()
        ok += 1
    print(f'-- {ok} match inserts')
    print()

    # Recalc priorities
    print('-- Step 5: Recalculate priorities')
    print("SELECT recalc_all_priorities();")
    print()

    # Re-sync form submissions
    print('-- Step 6: Re-sync form submissions from old clients table')
    print("""
DO $$
DECLARE rec RECORD; v_pid UUID; v_cid UUID; v_ret BOOLEAN;
BEGIN
  FOR rec IN SELECT DISTINCT ON (email) * FROM clients WHERE email IS NOT NULL AND TRIM(email)!='' ORDER BY email, id DESC
  LOOP
    SELECT id INTO v_pid FROM people WHERE email=LOWER(TRIM(rec.email)) LIMIT 1;
    IF v_pid IS NULL THEN SELECT id INTO v_pid FROM people WHERE legacy_id=rec.client_id LIMIT 1; END IF;
    IF v_pid IS NULL THEN
      v_ret := (LOWER(TRIM(COALESCE(rec.previous_cohort,'')))='yes');
      INSERT INTO people (legacy_id,id_type,first_name,last_name,preferred_name,email,phone,city,state,country,zip,is_veteran,military_status,branch_of_service,headshot_url)
      VALUES (rec.client_id,'client',TRIM(rec.first_name),TRIM(rec.last_name),NULLIF(TRIM(rec.preferred_name),''),LOWER(TRIM(rec.email)),NULLIF(TRIM(rec.phone),''),NULLIF(TRIM(rec.city),''),NULLIF(TRIM(rec.state),''),NULLIF(TRIM(rec.country),''),NULLIF(TRIM(rec.zip),''),TRUE,NULLIF(TRIM(rec.military_status),''),NULLIF(TRIM(rec.branch),''),NULLIF(TRIM(rec.headshot_url),''))
      ON CONFLICT (legacy_id) DO NOTHING
      RETURNING id INTO v_pid;
      IF v_pid IS NULL THEN SELECT id INTO v_pid FROM people WHERE email=LOWER(TRIM(rec.email)) LIMIT 1; END IF;
    END IF;
    IF v_pid IS NOT NULL THEN
      SELECT id INTO v_cid FROM cohorts WHERE LOWER(cohort_name)=LOWER(TRIM(COALESCE(rec.cohort,''))) LIMIT 1;
      IF v_cid IS NULL THEN SELECT id INTO v_cid FROM cohorts WHERE status='Active' ORDER BY year DESC LIMIT 1; END IF;
      IF v_cid IS NOT NULL THEN
        INSERT INTO client_applications (person_id,cohort_id,coaching_goals,coaching_type_interest,availability,bio,status,applied_at)
        VALUES (v_pid,v_cid,NULLIF(TRIM(rec.accomplishments),''),NULLIF(TRIM(rec.coaching_types),''),NULLIF(TRIM(rec.availability),''),NULLIF(TRIM(rec.bio),''),'Waitlisted',COALESCE(rec.created_at,now()))
        ON CONFLICT (person_id,cohort_id) DO NOTHING;
      END IF;
    END IF;
  END LOOP;
END $$;
""")

    # Set sequences
    print('-- Step 7: Set sequences')
    print("""
SELECT setval('client_id_seq', GREATEST(300, COALESCE((SELECT MAX(NULLIF(regexp_replace(vcp_id,'[^0-9]','','g'),'')::INT) FROM people WHERE id_type IN ('client','both')),300)));
SELECT setval('coach_id_seq', GREATEST(600, COALESCE((SELECT MAX(NULLIF(regexp_replace(vcp_id,'[^0-9]','','g'),'')::INT) FROM people WHERE id_type IN ('coach','both')),600)));
""")

    # Cleanup
    print('-- Step 8: Cleanup and verify')
    print('DROP TABLE IF EXISTS _pm;')
    print()
    print("""
SELECT 'People' AS tbl, COUNT(*) FROM people
UNION ALL SELECT 'Client Apps', COUNT(*) FROM client_applications
UNION ALL SELECT 'Coach Apps', COUNT(*) FROM coach_applications
UNION ALL SELECT 'Matches', COUNT(*) FROM new_matches;

SELECT c.cohort_name,
  (SELECT COUNT(*) FROM client_applications x WHERE x.cohort_id=c.id) AS clients,
  (SELECT COUNT(*) FROM coach_applications x WHERE x.cohort_id=c.id) AS coaches,
  (SELECT COUNT(*) FROM new_matches x WHERE x.cohort_id=c.id) AS matches
FROM cohorts c ORDER BY c.year, c.season;
""")

    wb.close()

if __name__ == '__main__':
    main()
```

### Running the Migration

```bash
# Generate SQL from spreadsheet
python vcp_resync.py VCP_Operations__DATA___12_.xlsx > resync.sql

# Split into parts (each under ~100KB for Supabase SQL Editor)
# Part 1: Lines from start through "Step 2:" marker
# Part 2: Lines from "Step 2:" through "Step 3:"
# Part 3: Lines from "Step 3:" through "Step 4:"
# Part 4: Lines from "Step 4:" through end

# IMPORTANT: Change TEMP TABLE to real TABLE in Part 1
# The _pm helper table must persist across SQL Editor tabs
# It's created as a real table and dropped in Part 4

# Run in Supabase SQL Editor in order:
# 1. Part 1 (setup + people)
# 2. Part 2 (client applications)
# 3. Part 3 (coach applications)
# 4. Part 4 (matches + priorities + verification)
```

### Key Migration Notes

- **Phone number is the reliable ID**: `legacy_id` = phone number (first 10 digits). This is the deduplication key across the entire system.
- **`_pm` table must be REAL, not TEMP**: Supabase SQL Editor runs each query in a separate session. TEMP tables don't persist.
- **Coach status mapping**: Both "Coach Dropped" and "Client Dropped" in the Coaches Masterlist map to "Dropped" for the coach's own record.
- **Missing coach applications**: Some coaches are matched to clients in the Clients tab but don't have a row in the Coaches tab for that cohort. The script auto-creates coach applications for these (Step 3b).
- **Email is NOT unique in people table**: 19 people have different emails across cohorts. `legacy_id` (phone) is the real unique key.

---

## Match Email Trigger (Step 7 — run after data migration)

See `vcp_match_emails.sql` for the full trigger function that sends emails via pg_net + Resend on new_matches INSERT. It pulls all dates/links from the cohorts table email config columns.

---

## Verification Queries

```sql
-- Check counts
SELECT 'People' AS tbl, COUNT(*) FROM people
UNION ALL SELECT 'Client Apps', COUNT(*) FROM client_applications
UNION ALL SELECT 'Coach Apps', COUNT(*) FROM coach_applications
UNION ALL SELECT 'Matches', COUNT(*) FROM new_matches;

-- Check priorities
SELECT priority, COUNT(*) FROM client_applications GROUP BY priority ORDER BY priority;
SELECT priority, COUNT(*) FROM coach_applications GROUP BY priority ORDER BY priority;

-- Check per-cohort data
SELECT c.cohort_name,
  (SELECT COUNT(*) FROM client_applications x WHERE x.cohort_id=c.id) AS clients,
  (SELECT COUNT(*) FROM coach_applications x WHERE x.cohort_id=c.id) AS coaches,
  (SELECT COUNT(*) FROM new_matches x WHERE x.cohort_id=c.id) AS matches
FROM cohorts c ORDER BY c.year, c.season;

-- Check cohort statuses
SELECT cohort_name, status FROM cohorts ORDER BY year, season;
```
