-- =============================================================================
-- 04_build_staging.sql
-- Builds cleaned tables in the stg schema from the untouched tm tables.
-- Safe to re-run: it only drops and rebuilds stg tables.
--
-- Club IDs: Manchester United = 985, Brighton & Hove Albion = 1237
-- Study window: seasons 2022/23 to 2025/26  (Transfermarkt season_start 2022-2025)
-- =============================================================================
DROP TABLE IF EXISTS stg.appearance, stg.transfer, stg.player, stg.game, stg.club CASCADE;

-- ---- 1. Clubs ----------------------------------------------------------------
CREATE TABLE stg.club AS
SELECT club_id, club_name, short_name
FROM (VALUES (985,  'Manchester United',        'Man Utd'),
             (1237, 'Brighton & Hove Albion',   'Brighton')) AS v(club_id, club_name, short_name);

-- ---- 2. Games (typed, with a readable season label) ---------------------------
CREATE TABLE stg.game AS
SELECT game_id,
       season                                           AS season_start,
       season || '/' || right((season + 1)::text, 2)    AS season_label,
       date                                             AS game_date,
       round,
       home_club_id, away_club_id,
       home_club_goals::int AS home_goals,
       away_club_goals::int AS away_goals,
       home_club_name, away_club_name
FROM tm.games
WHERE competition_id = 'GB1' AND season BETWEEN 2022 AND 2025;

-- ---- 3. Players (only those who appear or were transferred) ------------------
CREATE TABLE stg.player AS
SELECT p.player_id, p.name AS player_name, p.position,
       CASE p.position WHEN 'Goalkeeper' THEN 'GK'
                       WHEN 'Defender'   THEN 'DEF'
                       WHEN 'Midfield'   THEN 'MID'
                       WHEN 'Attack'     THEN 'FWD'
                       ELSE 'UNKNOWN' END AS position_group,
       p.sub_position, p.date_of_birth, p.country_of_citizenship
FROM tm.players p
WHERE p.player_id IN (SELECT player_id FROM tm.appearances)
   OR p.player_id IN (SELECT player_id FROM tm.transfers
                      WHERE from_club_id IN (985,1237) OR to_club_id IN (985,1237));

-- ---- 4. Appearances (one row per player per Premier League game) -------------
CREATE TABLE stg.appearance AS
SELECT a.appearance_id, a.game_id, a.player_id,
       a.player_club_id::int AS club_id, c.club_name,
       g.season_start, g.season_label, g.game_date,
       a.minutes_played::int AS minutes,
       a.goals::int AS goals, a.assists::int AS assists,
       a.yellow_cards::int AS yellow_cards, a.red_cards::int AS red_cards,
       p.player_name, p.position, p.position_group
FROM tm.appearances a
JOIN stg.game   g USING (game_id)
JOIN stg.club   c ON c.club_id = a.player_club_id
JOIN stg.player p USING (player_id);

-- ---- 5. Transfers involving the two clubs ------------------------------------
-- Why classification is needed: Transfermarkt stores loans as transfers with fee 0,
-- and the return from a loan as another fee-0 transfer. A fee of 0 therefore
-- means "free OR loan", and we must not count it as money spent.
CREATE TABLE stg.transfer AS
WITH base AS (
    SELECT t.player_id, t.transfer_date, t.transfer_season,
           (2000 + split_part(t.transfer_season, '/', 1)::int) AS season_start,
           CASE WHEN t.to_club_id IN (985,1237) THEN 'IN' ELSE 'OUT' END AS direction,
           CASE WHEN t.to_club_id IN (985,1237) THEN t.to_club_id   ELSE t.from_club_id END AS club_id,
           CASE WHEN t.to_club_id IN (985,1237) THEN t.from_club_id ELSE t.to_club_id   END AS other_club_id,
           CASE WHEN t.to_club_id IN (985,1237) THEN t.from_club_name ELSE t.to_club_name END AS other_club_name,
           t.transfer_fee, t.market_value_in_eur
    FROM tm.transfers t
    WHERE t.from_club_id IN (985,1237) OR t.to_club_id IN (985,1237)
),
flagged AS (
    SELECT b.*, c.club_name, c.short_name,
           (b.other_club_name ~ ('^' || c.short_name || ' (U[0-9]+|B)$')) AS is_internal,
           EXISTS (SELECT 1 FROM base x WHERE x.player_id = b.player_id AND x.club_id = b.club_id
                   AND x.other_club_id = b.other_club_id AND x.direction <> b.direction
                   AND x.transfer_date < b.transfer_date)  AS has_earlier_opposite,
           EXISTS (SELECT 1 FROM base x WHERE x.player_id = b.player_id AND x.club_id = b.club_id
                   AND x.other_club_id = b.other_club_id AND x.direction <> b.direction
                   AND x.transfer_date > b.transfer_date)  AS has_later_opposite
    FROM base b JOIN stg.club c ON c.club_id = b.club_id
)
SELECT f.player_id, p.player_name, p.position, p.position_group,
       f.transfer_date, f.transfer_season,
       (f.season_start::text || '/' || right((f.season_start + 1)::text, 2)) AS season_label,
       f.season_start,
       f.club_id, f.club_name, f.direction,
       f.other_club_id, f.other_club_name,
       f.transfer_fee AS fee_eur_raw,
       CASE WHEN f.is_internal              THEN 'INTERNAL'
            WHEN f.transfer_fee > 0         THEN 'PAID'
            WHEN f.transfer_fee = 0         THEN 'ZERO'
            ELSE 'MISSING' END AS fee_status,
       CASE
         WHEN f.is_internal AND f.direction = 'IN'  THEN 'ACADEMY_PROMOTION'
         WHEN f.is_internal AND f.direction = 'OUT' THEN 'INTERNAL_MOVE'
         WHEN f.transfer_fee > 0 AND f.direction = 'IN'  THEN 'PAID_SIGNING'
         WHEN f.transfer_fee > 0 AND f.direction = 'OUT' THEN 'PAID_SALE'
         WHEN f.direction = 'IN'  AND f.has_earlier_opposite THEN 'LOAN_RETURN'
         WHEN f.direction = 'IN'  AND f.has_later_opposite   THEN 'LOAN_IN_LIKELY'
         WHEN f.direction = 'IN'                              THEN 'FREE_OR_UNCLASSIFIED_IN'
         WHEN f.direction = 'OUT' AND f.has_earlier_opposite THEN 'LOAN_IN_ENDED'
         WHEN f.direction = 'OUT' AND f.has_later_opposite   THEN 'LOAN_OUT'
         ELSE 'FREE_OR_UNCLASSIFIED_OUT' END AS move_type,
       -- Money columns: only PAID moves carry a fee; everything else is NULL, never 0
       CASE WHEN f.transfer_fee > 0 AND NOT f.is_internal AND f.direction = 'IN'  THEN f.transfer_fee END AS spend_eur,
       CASE WHEN f.transfer_fee > 0 AND NOT f.is_internal AND f.direction = 'OUT' THEN f.transfer_fee END AS income_eur,
       f.market_value_in_eur AS market_value_eur
FROM flagged f
LEFT JOIN stg.player p USING (player_id)
WHERE f.season_start BETWEEN 2022 AND 2025;

CREATE INDEX ON stg.transfer (club_id, season_start);
CREATE INDEX ON stg.appearance (club_id, season_start, player_id);
