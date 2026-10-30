-- =============================================================================
-- 03_validation_checks.sql   (read-only: changes nothing)
-- Run each block separately in pgAdmin's Query Tool and compare with "Expected".
-- =============================================================================

-- CHECK 1: games per season (Expected: 380 for each of 2022, 2023, 2024, 2025)
SELECT season, count(*) AS games, min(date) AS first_game, max(date) AS last_game
FROM tm.games GROUP BY season ORDER BY season;

-- CHECK 2: each club appears in every game it played
-- (Expected: 38 games for each club in each season)
SELECT g.season, a.player_club_id AS club_id,
       count(DISTINCT a.game_id) AS games_with_appearances,
       count(DISTINCT a.player_id) AS players_used,
       sum(a.minutes_played) AS total_minutes
FROM tm.appearances a JOIN tm.games g USING (game_id)
GROUP BY g.season, a.player_club_id ORDER BY g.season, a.player_club_id;

-- CHECK 3: orphan records (Expected: every count = 0)
SELECT 'appearances without a game'   AS check_name, count(*) AS problems
FROM tm.appearances a LEFT JOIN tm.games g USING (game_id) WHERE g.game_id IS NULL
UNION ALL SELECT 'appearances without a player', count(*)
FROM tm.appearances a LEFT JOIN tm.players p USING (player_id) WHERE p.player_id IS NULL
UNION ALL SELECT 'appearances for other clubs', count(*)
FROM tm.appearances WHERE player_club_id NOT IN (985, 1237)
UNION ALL SELECT 'appearances with missing minutes', count(*)
FROM tm.appearances WHERE minutes_played IS NULL
UNION ALL SELECT 'appearing players with no position', count(*)
FROM tm.appearances a JOIN tm.players p USING (player_id) WHERE p.position IS NULL;

-- CHECK 4: transfer season labels match their dates
-- (Expected: each season runs 1 July to 30 June)
SELECT transfer_season, min(transfer_date) AS first_date, max(transfer_date) AS last_date, count(*) AS rows
FROM tm.transfers
WHERE transfer_season IN ('22/23','23/24','24/25','25/26')
  AND (from_club_id IN (985,1237) OR to_club_id IN (985,1237))
GROUP BY transfer_season ORDER BY transfer_season;

-- CHECK 5: fee status of every transfer involving the two clubs in the study window
-- (Shows why "fee = 0" cannot simply be treated as free: it includes loans)
SELECT CASE WHEN to_club_id IN (985,1237) THEN 'IN' ELSE 'OUT' END AS direction,
       CASE WHEN transfer_fee IS NULL THEN 'missing/undisclosed'
            WHEN transfer_fee = 0 THEN 'zero'
            ELSE 'paid' END AS fee_status,
       count(*) AS rows
FROM tm.transfers
WHERE transfer_season IN ('22/23','23/24','24/25','25/26')
  AND (from_club_id IN (985,1237) OR to_club_id IN (985,1237))
GROUP BY 1, 2 ORDER BY 1, 2;

-- CHECK 6: transfers directly between the two clubs (Expected: 0 rows)
SELECT * FROM tm.transfers
WHERE from_club_id IN (985,1237) AND to_club_id IN (985,1237)
  AND transfer_season IN ('22/23','23/24','24/25','25/26');
