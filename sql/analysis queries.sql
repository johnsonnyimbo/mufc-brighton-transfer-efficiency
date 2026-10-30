-- =============================================================================
-- 08_analysis_queries.sql   (Phase 4)  Run each query separately.
-- =============================================================================

-- Q1. Four-season totals: money and results, side by side
SELECT club_name,
       sum(spend_m) AS spend_m, sum(income_m) AS income_m, sum(net_spend_m) AS net_spend_m,
       sum(paid_signings) AS paid_signings, sum(points) AS points,
       round(sum(spend_m) / nullif(sum(points), 0), 2) AS spend_m_per_point
FROM mart.v_club_season GROUP BY club_name;

-- Q2. How good were the signings? Usage status of every paid signing, by club
SELECT club_name, usage_status, count(*) AS signings, round(sum(fee_m), 1) AS fee_m
FROM mart.v_signing_outcome WHERE move_type = 'PAID_SIGNING'
GROUP BY club_name, usage_status ORDER BY club_name, usage_status;

-- Q3. Share of minutes by cohort across all four seasons
SELECT club_name, cohort, sum(minutes) AS minutes,
       round(100.0 * sum(minutes) / sum(sum(minutes)) OVER (PARTITION BY club_name), 1) AS pct_of_minutes,
       sum(goals_assists) AS goal_involvements,
       round(100.0 * sum(goals_assists) / sum(sum(goals_assists)) OVER (PARTITION BY club_name), 1) AS pct_of_goal_involvements
FROM mart.v_cohort_share GROUP BY club_name, cohort ORDER BY club_name, cohort;

-- Q4. Is a bigger fee associated with more playing time or more output?
-- Pearson and Spearman (rank) correlation across paid signings. n is small,
-- so read these as indications, not proof, and never as causation.
WITH x AS (
    SELECT club_name, fee_m, minutes_first_season, ga_per90_first_season,
           rank() OVER (ORDER BY fee_m)                  AS r_fee,
           rank() OVER (ORDER BY minutes_first_season)   AS r_min
    FROM mart.v_signing_outcome WHERE move_type = 'PAID_SIGNING' AND fee_m IS NOT NULL
)
SELECT 'both clubs' AS scope, count(*) AS n,
       round(corr(fee_m, minutes_first_season)::numeric, 2) AS pearson_fee_vs_minutes,
       round(corr(r_fee, r_min)::numeric, 2)                AS spearman_fee_vs_minutes
FROM x
UNION ALL
SELECT club_name, count(*), round(corr(fee_m, minutes_first_season)::numeric, 2), NULL
FROM x GROUP BY club_name;

-- Q4b. Fee versus goal involvements per 90, only for signings with at least 450 minutes
SELECT 'both clubs' AS scope, count(*) AS n,
       round(corr(fee_m, ga_per90_first_season)::numeric, 2) AS pearson_fee_vs_ga_per90
FROM mart.v_signing_outcome
WHERE move_type = 'PAID_SIGNING' AND ga_per90_first_season IS NOT NULL
UNION ALL
SELECT club_name, count(*), round(corr(fee_m, ga_per90_first_season)::numeric, 2)
FROM mart.v_signing_outcome
WHERE move_type = 'PAID_SIGNING' AND ga_per90_first_season IS NOT NULL GROUP BY club_name;

-- Q5. The ten most expensive signings and what they gave in their first season
SELECT club_name, player_name, position_group, spend_season, fee_m,
       minutes_first_season, goals_assists_first_season, usage_status
FROM mart.v_signing_outcome WHERE move_type = 'PAID_SIGNING'
ORDER BY fee_m DESC LIMIT 10;

-- Q6. Recruitment trend across the four seasons (from the efficiency view)
SELECT club_name, season_label, paid_signings_who_played, fee_attributed_m, minutes,
       goals_assists, fee_m_per_1000_minutes, regulars
FROM mart.v_recruitment_efficiency ORDER BY club_name, season_start;