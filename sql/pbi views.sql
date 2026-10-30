-- =============================================================================
-- 09_powerbi_views.sql   (Phase 5)  Clean tables for Power BI (star-schema style).
-- dim_* are the filter lists; pbi_* are the facts. Safe to re-run.
-- =============================================================================
DROP VIEW IF EXISTS mart.pbi_recruitment, mart.pbi_cohort_share, mart.pbi_club_season,
                    mart.pbi_signing, mart.pbi_player_season,
                    mart.dim_position, mart.dim_season, mart.dim_club CASCADE;

CREATE VIEW mart.dim_club AS
SELECT club_name, short_name FROM stg.club;

CREATE VIEW mart.dim_season AS
SELECT DISTINCT season_start, season_label FROM stg.game;

CREATE VIEW mart.dim_position AS
SELECT * FROM (VALUES ('GK', 'Goalkeeper', 1), ('DEF', 'Defender', 2),
                      ('MID', 'Midfielder', 3), ('FWD', 'Forward', 4)) AS v(position_group, position_name, sort_order);

-- One row per club x season x player
CREATE VIEW mart.pbi_player_season AS
SELECT club_name, season_label, player_id, player_name, position_group,
       appearances, minutes, goals, assists, goals_assists,
       goals_per90, assists_per90, goals_assists_per90, qualifies_per90,
       cohort, signing_spend_season, signing_fee_eur / 1e6 AS signing_fee_m,
       fee_attributed_eur / 1e6 AS fee_attributed_m,
       market_value_at_transfer_eur / 1e6 AS market_value_at_transfer_m
FROM mart.player_season;

-- One row per incoming signing. season_label = season the player first played,
-- or the spend season if he never played (so every signing stays in the model).
CREATE VIEW mart.pbi_signing AS
SELECT signing_id, club_name, player_name, position_group, signed_from, move_type,
       coalesce((first_season_played::text || '/' || right((first_season_played + 1)::text, 2)), spend_season) AS season_label,
       spend_season, fee_m, market_value_m, minutes_first_season, pct_of_available_minutes,
       goals_assists_first_season, ga_per90_first_season, minutes_since_signing,
       usage_status, fee_m_per_1000_minutes
FROM mart.v_signing_outcome;

CREATE VIEW mart.pbi_club_season AS SELECT * FROM mart.v_club_season;
CREATE VIEW mart.pbi_cohort_share AS SELECT * FROM mart.v_cohort_share;
CREATE VIEW mart.pbi_recruitment AS SELECT * FROM mart.v_recruitment_efficiency;