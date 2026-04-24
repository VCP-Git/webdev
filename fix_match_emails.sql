-- ============================================================
-- SAFETY FIX: Remove auto-trigger, add guarded manual function
-- ============================================================

-- Step 1: Ensure trigger is dropped (idempotent)
DROP TRIGGER IF EXISTS trg_send_match_emails ON new_matches;

-- Step 2: Add emails_sent flag to new_matches if not exists
ALTER TABLE new_matches ADD COLUMN IF NOT EXISTS emails_sent BOOLEAN DEFAULT FALSE;

-- Step 3: Neuter the old trigger function so if anyone re-attaches
--         it as a trigger, it does nothing harmful
CREATE OR REPLACE FUNCTION public.send_match_emails()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- AUTO-TRIGGER DISABLED: emails must be sent manually via
  -- SELECT send_match_email('<match_uuid>') from the dashboard.
  -- This function intentionally does nothing.
  RETURN NEW;
END;
$$;

-- Step 4: Create the new safe, human-invoked function
CREATE OR REPLACE FUNCTION public.send_match_email(p_match_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_match                   RECORD;
  v_client_app              RECORD;
  v_coach_app               RECORD;
  v_cohort                  RECORD;
  v_client_html             TEXT;
  v_coach_html              TEXT;
  v_client_name             TEXT;
  v_coach_name              TEXT;
  v_group_dates_html        TEXT;
  v_forum_dates_html        TEXT;
  v_supervision_dates_html  TEXT;
  -- Earliest cohort that may receive emails (Spring 2025 = 20251)
  v_min_cohort_numeric      INT := 20251;
BEGIN

  -- ── GUARD 1: match must exist ─────────────────────────────
  SELECT * INTO v_match FROM new_matches WHERE id = p_match_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'Match not found: ' || p_match_id::text);
  END IF;

  -- ── GUARD 2: cohort must be Spring 2025 or newer ──────────
  SELECT * INTO v_cohort FROM cohorts WHERE id = v_match.cohort_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Cohort not found');
  END IF;

  IF v_cohort.cohort_numeric IS NULL OR v_cohort.cohort_numeric < v_min_cohort_numeric THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'BLOCKED: ' || v_cohort.cohort_name
               || ' is a historical cohort (before Spring 2025).'
               || ' Match emails are only allowed for current and future cohorts.',
      'cohort', v_cohort.cohort_name,
      'cohort_numeric', v_cohort.cohort_numeric
    );
  END IF;

  -- ── GUARD 3: don't double-send ────────────────────────────
  IF v_match.emails_sent = true THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Emails already sent for this match. To resend, an admin must clear the emails_sent flag.',
      'match_id', p_match_id
    );
  END IF;

  -- Get client application + person
  SELECT ca.*, p.first_name AS p_first, p.last_name AS p_last,
         p.preferred_name AS p_preferred, p.email AS p_email,
         p.headshot_url AS p_headshot, p.branch_of_service AS p_branch
  INTO v_client_app
  FROM client_applications ca
  JOIN people p ON p.id = ca.person_id
  WHERE ca.id = v_match.client_application_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Client application not found');
  END IF;

  -- Get coach application + person
  SELECT ka.*, p.first_name AS p_first, p.last_name AS p_last,
         p.preferred_name AS p_preferred, p.email AS p_email,
         p.headshot_url AS p_headshot
  INTO v_coach_app
  FROM coach_applications ka
  JOIN people p ON p.id = ka.person_id
  WHERE ka.id = v_match.coach_application_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Coach application not found');
  END IF;

  -- Names (prefer preferred_name)
  v_client_name := COALESCE(NULLIF(v_client_app.p_preferred, ''), v_client_app.p_first);
  v_coach_name  := COALESCE(NULLIF(v_coach_app.p_preferred,  ''), v_coach_app.p_first);

  v_group_dates_html       := REPLACE(COALESCE(v_cohort.group_coaching_dates, ''), E'\n', '<br>');
  v_forum_dates_html       := REPLACE(COALESCE(v_cohort.coaching_forum_dates, ''), E'\n', '<br>');
  v_supervision_dates_html := REPLACE(COALESCE(v_cohort.coaching_supervision_dates, ''), E'\n', '<br>');

  -- ════════════════════════ CLIENT EMAIL ════════════════════════
  v_client_html :=
    '<!DOCTYPE html><html><body style="margin:0;padding:0;background:#f4f4f7;font-family:Arial,sans-serif;">'
    || '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;padding:40px 20px;"><tr><td align="center">'
    || '<table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;">'
    || '<tr><td style="background:#343963;padding:40px;text-align:center;">'
    || '<h1 style="color:#fff;font-size:24px;margin:0 0 8px;">Veterans Coaching Project</h1>'
    || '<p style="color:rgba(255,255,255,0.7);font-size:14px;margin:0;">' || COALESCE(v_cohort.cohort_label, v_cohort.cohort_name) || '</p>'
    || '</td></tr>'
    || '<tr><td style="padding:40px;">'
    || '<p style="color:#343963;font-size:16px;line-height:1.6;margin:0 0 16px;">Hello ' || v_client_name || ',</p>'
    || '<p style="color:#343963;font-size:16px;line-height:1.6;margin:0 0 16px;"><strong>Congratulations!</strong> You have been matched with a VCP coach for the Veterans Coaching Project (VCP) '
    || COALESCE(v_cohort.cohort_label, v_cohort.cohort_name) || '. We thank you for volunteering to participate!</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 20px;">As a reminder, our goal is to provide you with 15-18 individual one-hour coaching sessions throughout the coaching engagement.</p>'
    || '<div style="background:#f0f1f5;border-left:4px solid #343963;padding:20px 24px;border-radius:0 8px 8px 0;margin:0 0 24px;">'
    || '<p style="color:#343963;font-size:18px;font-weight:bold;margin:0 0 4px;">You have been paired with:</p>'
    || '<p style="color:#343963;font-size:20px;font-weight:bold;margin:0;">' || v_coach_app.p_first || ' ' || v_coach_app.p_last || '</p>'
    || '<p style="color:#646C91;font-size:14px;margin:4px 0 0;">They are excited to support you on this transformative journey.</p>'
    || '</div>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 12px;">Attached, you will find your coach''s profile. Your profile will also be shared with your coach to help them get to know you better!</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 12px;">The <strong>Participant Waiver and Release Form</strong> requires your signature to continue participating in the cohort.</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 24px;">The <strong>Coaching Agreement</strong> will be forwarded to you by your coach. Please sign and return it to your coach.</p>';

  IF v_cohort.client_intro_date IS NOT NULL THEN
    v_client_html := v_client_html
      || '<div style="background:#f8f8fa;border-radius:8px;padding:20px 24px;margin:0 0 16px;">'
      || '<p style="color:#343963;font-size:15px;font-weight:bold;margin:0 0 12px;">Upcoming Events</p>'
      || '<p style="color:#455560;font-size:14px;line-height:1.8;margin:0;">'
      || '<strong>Clients Introduction Meeting (' || v_cohort.client_intro_date || '):</strong><br>'
      || CASE WHEN v_cohort.client_intro_replay_url IS NOT NULL
           THEN 'Watch the replay: <a href="' || v_cohort.client_intro_replay_url || '" style="color:#343963;">Click here</a><br><br>'
           ELSE '<br>' END
      || '<strong>VCP Kick-Off Meeting (' || COALESCE(v_cohort.kickoff_date, 'TBD') || '):</strong><br>'
      || CASE WHEN v_cohort.kickoff_replay_url IS NOT NULL
           THEN 'Watch the replay: <a href="' || v_cohort.kickoff_replay_url || '" style="color:#343963;">Click here</a><br><br>'
           ELSE '<br>' END
      || '</p></div>';
  END IF;

  IF v_cohort.group_coaching_dates IS NOT NULL THEN
    v_client_html := v_client_html
      || '<div style="background:#f8f8fa;border-radius:8px;padding:20px 24px;margin:0 0 16px;">'
      || '<p style="color:#343963;font-size:14px;font-weight:bold;margin:0 0 8px;">Group Coaching (attend at least 2 sessions):</p>'
      || '<p style="color:#455560;font-size:13px;line-height:1.8;margin:0;">' || v_group_dates_html || '</p>'
      || '<p style="color:#646C91;font-size:12px;margin:8px 0 0;">Duration: 1 hour | Attendees: Veterans, Spouses, and/or Caregivers</p>'
      || '</div>';
  END IF;

  v_client_html := v_client_html
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:20px 0 0;">If you have any questions, please reach out to the VCP Veteran Engagement Team at <a href="mailto:engage@veteranscoachingproject.org" style="color:#343963;">engage@veteranscoachingproject.org</a>.</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:16px 0 0;">We look forward to working with you and wish you a successful and rewarding VCP experience!</p>'
    || '<p style="color:#343963;font-size:15px;margin:20px 0 0;"><strong>Warmest Regards,</strong><br>Veterans Coaching Project</p>'
    || '</td></tr>'
    || '<tr><td style="background:#f8f8fa;padding:24px 40px;text-align:center;border-top:1px solid #e8e9ee;">'
    || '<p style="color:#646C91;font-size:12px;margin:0;">Veterans Coaching Project | veteranscoachingproject.org</p>'
    || '</td></tr></table></td></tr></table></body></html>';

  -- ════════════════════════ COACH EMAIL ════════════════════════
  v_coach_html :=
    '<!DOCTYPE html><html><body style="margin:0;padding:0;background:#f4f4f7;font-family:Arial,sans-serif;">'
    || '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;padding:40px 20px;"><tr><td align="center">'
    || '<table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;">'
    || '<tr><td style="background:#455560;padding:40px;text-align:center;">'
    || '<h1 style="color:#fff;font-size:24px;margin:0 0 8px;">Veterans Coaching Project</h1>'
    || '<p style="color:rgba(255,255,255,0.7);font-size:14px;margin:0;">' || COALESCE(v_cohort.cohort_label, v_cohort.cohort_name) || '</p>'
    || '</td></tr>'
    || '<tr><td style="padding:40px;">'
    || '<p style="color:#343963;font-size:16px;line-height:1.6;margin:0 0 16px;">Hello ' || v_coach_name || ',</p>'
    || '<p style="color:#343963;font-size:16px;line-height:1.6;margin:0 0 16px;"><strong>Congratulations!</strong> You have been matched with a veteran client for the Veteran''s Coaching Project (VCP) '
    || COALESCE(v_cohort.cohort_label, v_cohort.cohort_name) || '.</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 20px;">As a reminder, our goal is to provide our clients with 15-18 individual coaching sessions throughout the coaching engagement.</p>'
    || '<div style="background:#f0f1f5;border-left:4px solid #455560;padding:20px 24px;border-radius:0 8px 8px 0;margin:0 0 24px;">'
    || '<p style="color:#343963;font-size:18px;font-weight:bold;margin:0 0 4px;">You have been paired with:</p>'
    || '<p style="color:#343963;font-size:20px;font-weight:bold;margin:0;">' || v_client_app.p_first || ' ' || v_client_app.p_last || '</p>'
    || '</div>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 12px;">Attached, you will find your client''s completed profile. Your profile will be shared with your client as well.</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 12px;">The <strong>Participant Waiver and Release Form</strong> and the <strong>Release Waiver Form</strong> require your signature.</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:0 0 24px;">The <strong>Coaching Agreement</strong> requires both your signature and your client''s signature. Please sign and send it to your client, then return the fully signed document to VCP.</p>';

  IF v_cohort.kickoff_date IS NOT NULL THEN
    v_coach_html := v_coach_html
      || '<div style="background:#f0f1f5;border-radius:8px;padding:16px 20px;margin:0 0 16px;">'
      || '<p style="color:#343963;font-size:14px;margin:0;"><strong>Please review and sign all attached documents prior to the VCP Kickoff Meeting on '
      || v_cohort.kickoff_date || ' at ' || COALESCE(v_cohort.kickoff_time, '6:00 pm EST') || '.</strong> This event is mandatory.</p>'
      || '</div>';
  END IF;

  IF v_cohort.coaching_forum_dates IS NOT NULL THEN
    v_coach_html := v_coach_html
      || '<div style="background:#f8f8fa;border-radius:8px;padding:20px 24px;margin:0 0 16px;">'
      || '<p style="color:#343963;font-size:14px;font-weight:bold;margin:0 0 8px;">Coaching Forum Dates (attend at least 1 session):</p>'
      || '<p style="color:#455560;font-size:13px;line-height:1.8;margin:0;">' || v_forum_dates_html || '</p>'
      || '</div>';
  END IF;

  IF v_cohort.coaching_supervision_dates IS NOT NULL THEN
    v_coach_html := v_coach_html
      || '<div style="background:#f8f8fa;border-radius:8px;padding:20px 24px;margin:0 0 16px;">'
      || '<p style="color:#343963;font-size:14px;font-weight:bold;margin:0 0 8px;">Coaching Supervision Dates (attend at least 1 session):</p>'
      || '<p style="color:#455560;font-size:13px;line-height:1.8;margin:0;">' || v_supervision_dates_html || '</p>'
      || '</div>';
  END IF;

  v_coach_html := v_coach_html
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:20px 0 0;">If you have any questions, feel free to reach out at <a href="mailto:engage@veteranscoachingproject.org" style="color:#343963;">engage@veteranscoachingproject.org</a>.</p>'
    || '<p style="color:#455560;font-size:15px;line-height:1.6;margin:16px 0 0;">We look forward to working with you and wish you a successful and rewarding VCP experience!</p>'
    || '<p style="color:#343963;font-size:15px;margin:20px 0 0;"><strong>Warmest Regards,</strong><br>Veterans Coaching Project</p>'
    || '</td></tr>'
    || '<tr><td style="background:#f8f8fa;padding:24px 40px;text-align:center;border-top:1px solid #e8e9ee;">'
    || '<p style="color:#646C91;font-size:12px;margin:0;">Veterans Coaching Project | veteranscoachingproject.org</p>'
    || '</td></tr></table></td></tr></table></body></html>';

  -- ════════════════════════ SEND VIA RESEND ════════════════════════

  IF v_client_app.p_email IS NOT NULL AND v_client_app.p_email != '' THEN
    PERFORM net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer re_7hYCPAuo_FrVeAzWzaxmEwNEXUXFYN2bH', 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
        'from',     'Veterans Coaching Project <engage@veteranscoachingproject.org>',
        'to',       v_client_app.p_email,
        'subject',  'Congratulations! You''ve Been Matched — VCP ' || COALESCE(v_cohort.cohort_label, v_cohort.cohort_name),
        'html',     v_client_html,
        'reply_to', 'engage@veteranscoachingproject.org'
      )
    );
  END IF;

  IF v_coach_app.p_email IS NOT NULL AND v_coach_app.p_email != '' THEN
    PERFORM net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer re_7hYCPAuo_FrVeAzWzaxmEwNEXUXFYN2bH', 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
        'from',     'Veterans Coaching Project <engage@veteranscoachingproject.org>',
        'to',       v_coach_app.p_email,
        'subject',  'You''ve Been Matched with a Veteran Client — VCP ' || COALESCE(v_cohort.cohort_label, v_cohort.cohort_name),
        'html',     v_coach_html,
        'reply_to', 'engage@veteranscoachingproject.org'
      )
    );
  END IF;

  -- Internal notification to VCP team
  PERFORM net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer re_7hYCPAuo_FrVeAzWzaxmEwNEXUXFYN2bH', 'Content-Type', 'application/json'),
    body    := jsonb_build_object(
      'from',    'Veterans Coaching Project <engage@veteranscoachingproject.org>',
      'to',      'engage@veteranscoachingproject.org',
      'subject', 'Match Emails Sent: ' || v_client_app.p_first || ' ' || v_client_app.p_last
                 || ' ↔ ' || v_coach_app.p_first || ' ' || v_coach_app.p_last,
      'html',    '<p><strong>Match emails sent manually.</strong></p>'
                 || '<p>Client: ' || v_client_app.p_first || ' ' || v_client_app.p_last || ' (' || COALESCE(v_client_app.p_email, '—') || ')</p>'
                 || '<p>Coach: '  || v_coach_app.p_first  || ' ' || v_coach_app.p_last  || ' (' || COALESCE(v_coach_app.p_email,  '—') || ')</p>'
                 || '<p>Cohort: ' || v_cohort.cohort_name || '</p>'
    )
  );

  -- Mark as sent so we never double-send
  UPDATE new_matches SET emails_sent = true, updated_at = now() WHERE id = p_match_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'client',            v_client_app.p_first || ' ' || v_client_app.p_last,
    'coach',             v_coach_app.p_first  || ' ' || v_coach_app.p_last,
    'cohort',            v_cohort.cohort_name,
    'client_email_sent', (v_client_app.p_email IS NOT NULL AND v_client_app.p_email != ''),
    'coach_email_sent',  (v_coach_app.p_email  IS NOT NULL AND v_coach_app.p_email  != '')
  );
END;
$$;

-- Verify trigger is gone
SELECT 'Trigger check' AS step,
       COUNT(*) AS triggers_remaining
FROM information_schema.triggers
WHERE trigger_name = 'trg_send_match_emails';
