-- =============================================================================
-- 07_analysis_views.sql   (Phase 4)  Builds analysis views in the mart schema.
-- Power BI will read these views. Safe to re-run.
-- Performance here means minutes, goals and assists from Transfermarkt data.
-- (No player ratings are used in this version of the project.)
-- =============================================================================
DROP VIEW IF EXISTS mart.v_recruitment_efficiency, mart.v_cohort_share,
                    mart.v_signing_outcome, mart.v_club_season CASCADE;

-- ---- 1. Club x season: money, league results ---------------------------------
CREATE VIEW mart.v_club_season AS
WITH fin AS (
    SELECT club_id, season_start, season_label,
           sum(spend_eur)  AS spend_eur,
           sum(income_eur) AS income_eur,
           count(*) FILTER (WHERE move_type = 'PAID_SIGNING') AS paid_signings,
           count(*) FILTER (WHERE move_type = 'PAID_SALE')    AS paid_sales
    FROM stg.transfer GROUP BY club_id, season_start, season_label
),
res AS (
    SELECT club_id, season_start,
           sum(pts) AS points, sum(gf) AS goals_for, sum(ga) AS goals_against
    FROM (
        SELECT home_club_id AS club_id, season_start, home_goals AS gf, away_goals AS ga,
               CASE WHEN home_goals > away_goals THEN 3 WHEN home_goals = away_goals THEN 1 ELSE 0 END AS pts
        FROM stg.game WHERE home_club_id IN (985,1237)
        UNION ALL
        SELECT away_club_id, season_start, away_goals, home_goals,
               CASE WHEN away_goals > home_goals THEN 3 WHEN away_goals = home_goals THEN 1 ELSE 0 END
        FROM stg.game WHERE away_club_id IN (985,1237)
    ) x GROUP BY club_id, season_start
)
SELECT c.club_name, f.season_label, f.season_start,
       round(f.spend_eur / 1e6, 1)  AS spend_m,
       round(f.income_eur / 1e6, 1) AS income_m,
       round((coalesce(f.spend_eur,0) - coalesce(f.income_eur,0)) / 1e6, 1) AS net_spend_m,
       f.paid_signings, f.paid_sales,
       r.points, r.goals_for, r.goals_against, r.goals_for - r.goals_against AS goal_difference
FROM fin f JOIN stg.club c USING (club_id) LEFT JOIN res r USING (club_id, season_start);

-- ---- 2. One row per signing, with a plain-language usage status ---------------
-- Usage is measured against the 3,420 minutes available in a 38-game season.
-- Status thresholds (a judgement call, shown on the dashboard):
--   Did not play < 1 minute | Fringe < 900 | Rotation 900-1,999 | Regular >= 2,000
CREATE VIEW mart.v_signing_outcome AS
SELECT s.signing_id, s.club_name, s.player_name, s.position_group, s.signed_from,
       s.spend_season, s.first_season_played, s.move_type,
       round(s.fee_eur / 1e6, 1) AS fee_m,
       round(s.market_value_at_transfer_eur / 1e6, 1) AS market_value_m,
       coalesce(s.minutes_first_season, 0) AS minutes_first_season,
       round(coalesce(s.minutes_first_season, 0) / 3420.0 * 100, 0) AS pct_of_available_minutes,
       p.goals_assists AS goals_assists_first_season,
       p.goals_assists_per90 AS ga_per90_first_season,
       coalesce(s.minutes_since_signing, 0) AS minutes_since_signing,
       CASE WHEN coalesce(s.minutes_first_season, 0) = 0     THEN '1 Did not play'
            WHEN s.minutes_first_season < 900                THEN '2 Fringe'
            WHEN s.minutes_first_season < 2000               THEN '3 Rotation'
            ELSE                                                  '4 Regular' END AS usage_status,
       CASE WHEN s.minutes_first_season > 0
            THEN round(s.fee_eur / 1e6 / (s.minutes_first_season / 1000.0), 2) END AS fee_m_per_1000_minutes
FROM mart.signing s
LEFT JOIN mart.player_season p
  ON p.player_id = s.player_id AND p.club_id = s.club_id AND p.season_start = s.first_season_played;

-- ---- 3. Who plays? Share of club minutes and goal involvements by cohort ----
CREATE VIEW mart.v_cohort_share AS
SELECT club_name, season_label, season_start, cohort,
       count(*) AS players,
       sum(minutes) AS minutes,
       round(100.0 * sum(minutes) / sum(sum(minutes)) OVER (PARTITION BY club_name, season_start), 1) AS pct_of_club_minutes,
       sum(goals_assists) AS goals_assists,
       round(100.0 * sum(goals_assists) / nullif(sum(sum(goals_assists)) OVER (PARTITION BY club_name, season_start), 0), 1) AS pct_of_club_goal_involvements
FROM mart.player_season
GROUP BY club_name, season_label, season_start, cohort;

-- ---- 4. Recruitment efficiency by club and season of first appearance --------
CREATE VIEW mart.v_recruitment_efficiency AS
SELECT s.club_name, s.first_season_played AS season_start,
       (s.first_season_played::text || '/' || right((s.first_season_played + 1)::text, 2)) AS season_label,
       count(*)                                               AS paid_signings_who_played,
       round(sum(s.fee_eur) / 1e6, 1)                         AS fee_attributed_m,
       sum(s.minutes_first_season)                            AS minutes,
       sum(p.goals_assists)                                   AS goals_assists,
       round(sum(s.fee_eur) / 1e6 / (sum(s.minutes_first_season) / 1000.0), 2) AS fee_m_per_1000_minutes,
       round(sum(s.fee_eur) / 1e6 / nullif(sum(p.goals_assists), 0), 1)        AS fee_m_per_goal_involvement,
       count(*) FILTER (WHERE s.minutes_first_season >= 2000) AS regulars
FROM mart.signing s
LEFT JOIN mart.player_season p
  ON p.player_id = s.player_id AND p.club_id = s.club_id AND p.season_start = s.first_season_played
WHERE s.move_type = 'PAID_SIGNING' AND s.first_season_played IS NOT NULL
GROUP BY s.club_name, s.first_season_played;
