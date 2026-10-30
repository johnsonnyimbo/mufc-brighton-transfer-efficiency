-- =============================================================================
-- 05_build_marts.sql   (Phase 3: fee attribution and recruitment cohorts)
-- Builds two analysis tables in the mart schema from the stg tables.
-- Safe to re-run.
--
-- FEE ATTRIBUTION RULES
--  1. A fee belongs to ONE transfer and is counted ONCE: in the season the signed
--     player first plays for the club (column fee_attributed_eur on player_season).
--  2. The original fee is repeated in later seasons only in the information column
--     signing_fee_eur, which must never be summed.
--  3. Zero or missing fees are NOT treated as money spent: they stay NULL.
--  4. A player who is signed but never plays has a row in mart.signing but none in
--     mart.player_season. That money is spend with no on-pitch return.
--  5. spend_season is the Transfermarkt season label (1 July to 30 June window);
--     first_season_played can be a season later (e.g. a June signing).
-- =============================================================================
DROP TABLE IF EXISTS mart.player_season, mart.signing CASCADE;

-- ---- mart.signing : one row per incoming signing (paid, free/unclassified, loan-in)
CREATE TABLE mart.signing AS
WITH s AS (
    SELECT row_number() OVER (ORDER BY club_id, transfer_date, player_id) AS signing_id,
           t.club_id, t.club_name, t.player_id, t.player_name, t.position, t.position_group,
           t.transfer_date, t.season_label AS spend_season, t.season_start AS spend_season_start,
           t.move_type, t.other_club_name AS signed_from, t.spend_eur AS fee_eur,
           t.market_value_eur AS market_value_at_transfer_eur
    FROM stg.transfer t
    WHERE t.direction = 'IN' AND t.move_type IN ('PAID_SIGNING','FREE_OR_UNCLASSIFIED_IN','LOAN_IN_LIKELY')
),
first_game AS (
    SELECT s.signing_id, min(a.game_date) AS first_game_date
    FROM s JOIN stg.appearance a
      ON a.player_id = s.player_id AND a.club_id = s.club_id AND a.game_date >= s.transfer_date
    GROUP BY s.signing_id
),
fs AS (
    SELECT f.signing_id, f.first_game_date,
           (SELECT a.season_start FROM stg.appearance a
            JOIN s ON s.signing_id = f.signing_id
            WHERE a.player_id = s.player_id AND a.club_id = s.club_id AND a.game_date = f.first_game_date
            LIMIT 1) AS first_season_played
    FROM first_game f
)
SELECT s.*, fs.first_game_date, fs.first_season_played,
       (SELECT sum(a.minutes) FROM stg.appearance a
         WHERE a.player_id = s.player_id AND a.club_id = s.club_id
           AND a.season_start = fs.first_season_played)                       AS minutes_first_season,
       (SELECT sum(a.minutes) FROM stg.appearance a
         WHERE a.player_id = s.player_id AND a.club_id = s.club_id
           AND a.game_date >= s.transfer_date)                                AS minutes_since_signing,
       (SELECT sum(a.goals + a.assists) FROM stg.appearance a
         WHERE a.player_id = s.player_id AND a.club_id = s.club_id
           AND a.game_date >= s.transfer_date)                                AS goals_assists_since_signing
FROM s LEFT JOIN fs USING (signing_id);

-- ---- mart.player_season : one row per club x season x player ----------------
CREATE TABLE mart.player_season AS
WITH agg AS (
    SELECT club_id, club_name, season_start, season_label, player_id, player_name, position, position_group,
           count(*) FILTER (WHERE minutes > 0) AS appearances,
           sum(minutes) AS minutes,
           sum(goals) AS goals, sum(assists) AS assists, sum(goals + assists) AS goals_assists,
           sum(yellow_cards) AS yellow_cards, sum(red_cards) AS red_cards
    FROM stg.appearance
    GROUP BY club_id, club_name, season_start, season_label, player_id, player_name, position, position_group
),
joined AS (
    SELECT a.*, sg.signing_id, sg.move_type AS signing_move_type, sg.fee_eur AS signing_fee_eur,
           sg.spend_season AS signing_spend_season, sg.first_season_played,
           sg.market_value_at_transfer_eur,
           EXISTS (SELECT 1 FROM stg.transfer t WHERE t.player_id = a.player_id AND t.club_id = a.club_id
                   AND t.move_type = 'ACADEMY_PROMOTION') AS is_academy_promotion
    FROM agg a
    LEFT JOIN LATERAL (
        SELECT s.* FROM mart.signing s
        WHERE s.player_id = a.player_id AND s.club_id = a.club_id
          AND s.first_season_played IS NOT NULL AND s.first_season_played <= a.season_start
        ORDER BY s.transfer_date DESC LIMIT 1
    ) sg ON TRUE
)
SELECT club_id, club_name, season_start, season_label, player_id, player_name, position, position_group,
       appearances, minutes, goals, assists, goals_assists, yellow_cards, red_cards,
       CASE WHEN minutes >= 450 THEN round(goals::numeric * 90 / minutes, 3)         END AS goals_per90,
       CASE WHEN minutes >= 450 THEN round(assists::numeric * 90 / minutes, 3)       END AS assists_per90,
       CASE WHEN minutes >= 450 THEN round(goals_assists::numeric * 90 / minutes, 3) END AS goals_assists_per90,
       (minutes >= 450) AS qualifies_per90,
       CASE
         WHEN signing_id IS NULL AND is_academy_promotion THEN 'ACADEMY_PRODUCT'
         WHEN signing_id IS NULL                          THEN 'EXISTING_SQUAD'
         WHEN signing_move_type = 'LOAN_IN_LIKELY'        THEN 'LOAN_IN'
         WHEN first_season_played = season_start AND signing_move_type = 'PAID_SIGNING' THEN 'NEW_SIGNING_PAID'
         WHEN first_season_played = season_start          THEN 'NEW_SIGNING_ZERO_FEE'
         ELSE 'SIGNED_EARLIER_IN_WINDOW'
       END AS cohort,
       signing_spend_season,
       signing_fee_eur,                                                  -- information only, never sum
       CASE WHEN first_season_played = season_start AND signing_move_type = 'PAID_SIGNING'
            THEN signing_fee_eur END AS fee_attributed_eur,              -- safe to sum
       market_value_at_transfer_eur
FROM joined;

CREATE INDEX ON mart.player_season (club_id, season_start);
CREATE INDEX ON mart.signing (club_id, spend_season_start);