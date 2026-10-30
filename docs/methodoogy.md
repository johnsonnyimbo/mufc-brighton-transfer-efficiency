# Methodology

Status: draft. Updated as each phase is completed.

## Question
How effectively do Manchester United and Brighton convert transfer spending into player performance?

## Scope
- Clubs: Manchester United, Brighton & Hove Albion
- Competition: Premier League
- Seasons: 2022/23 to 2025/26

## Data sources
| Source | Used for | Notes |
|---|---|---|
| Transfermarkt | Transfers, fees, market values, games, appearances | Loaded into schema `tm` |
| FBref | Player performance statistics (Phase to be completed) | Allows position-appropriate comparison |

## Definitions

**Season.** Transfermarkt's `transfer_season` label is used, so 22/23 covers both the summer and January windows of that season.

**Spend.** Sum of fees on incoming transfers with a fee above 0, in euros.

**Income.** Sum of fees on outgoing transfers with a fee above 0, in euros.

**Net spend.** Spend minus income.

**Zero or missing fees.** A fee of 0 means a free transfer, loan or academy promotion. A missing fee means the fee was undisclosed. Neither is treated as €0 spent. These players are counted as signings but excluded from any "performance per euro spent" measure.

**No spreading of fees.** A fee belongs to the player's signing season only. A sensitivity check that spreads fees across contract years may be added later.

**Recruited vs existing squad.** Players signed from 22/23 to 25/26 form the "recruited" group. All other players are the "existing squad".

**Performance.** Compared within position groups, because raw goals and assists favour attackers. Metrics are per 90 minutes, with a minimum-minutes threshold (value to be decided and recorded here).

## Known issues
- The FBref file labelled Brighton 2025/26 was found to be a copy of 2024/25 and must be replaced before use.
- Assist definitions differ slightly between Transfermarkt and FBref. The authoritative source per metric is: (to be decided).
- Several signings each season have free or undisclosed fees, so spend totals understate total recruitment.

## Limitations
- Two clubs only.
- Fees are not adjusted for inflation or contract length.