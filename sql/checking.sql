-- =============================================================================
-- 06_phase3_checks.sql   (read-only)  Run each block separately.
-- =============================================================================

-- CHECK A: every paid euro is accounted for.
-- Expected: attributed_m + never_played_m = total_paid_signings_m for each club
--   Man Utd  : 933.72 + 4.00  = 937.72
--   Brighton : 497.50 + 26.50 = 524.00
SELECT s.club_name,
       round(sum(s.fee_eur) / 1e6, 2)                                              AS total_paid_signings_m,
       round(sum(s.fee_eur) FILTER (WHERE s.first_season_played IS NOT NULL) / 1e6, 2) AS played_m,
       round(sum(s.fee_eur) FILTER (WHERE s.first_season_played IS NULL) / 1e6, 2)     AS never_played_m,
       (SELECT round(sum(p.fee_attributed_eur) / 1e6, 2) FROM mart.player_season p
         WHERE p.club_id = s.club_id)                                              AS attributed_m
FROM mart.signing s WHERE s.move_type = 'PAID_SIGNING'
GROUP BY s.club_id, s.club_name;

-- CHECK B: signings who never played a Premier League minute for the club
-- Expected: 6 rows (Osman 19.5m and Yalcouyé 7.0m at Brighton; Leon 4.0m at Man Utd;
--           plus Cozier-Duberry, Dubravka, Butland with no fee)
SELECT club_name, player_name, spend_season, transfer_date, move_type,
       round(fee_eur / 1e6, 1) AS fee_m, signed_from
FROM mart.signing WHERE first_season_played IS NULL ORDER BY club_name, transfer_date;

-- CHECK C: signings whose first playing season differs from the spend season
-- Expected: Adingra (2022/23 spend, first played 2023), Tzimas, Bayindir
SELECT club_name, player_name, spend_season, first_season_played, round(fee_eur / 1e6, 1) AS fee_m
FROM mart.signing
WHERE move_type = 'PAID_SIGNING' AND spend_season_start <> first_season_played
ORDER BY club_name, transfer_date;

-- CHECK D: cohort overview. Expected row counts of player-seasons:
--   Brighton: ACADEMY 10, EXISTING 54, LOAN_IN 2, NEW_PAID 25, NEW_ZERO_FEE 3, SIGNED_EARLIER 25
--   Man Utd : ACADEMY 17, EXISTING 48, LOAN_IN 4, NEW_PAID 19, NEW_ZERO_FEE 2, SIGNED_EARLIER 25
SELECT club_name, cohort, count(*) AS player_seasons, sum(minutes) AS minutes,
       round(sum(fee_attributed_eur) / 1e6, 1) AS fee_attributed_m
FROM mart.player_season GROUP BY club_name, cohort ORDER BY club_name, cohort;