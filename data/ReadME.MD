# Data

Raw data files are not committed to this repository (see `.gitignore`). To reproduce the analysis, download the source files, filter them with the pandas script, and place the outputs in `dataraw`.

## Transfermarkt
Downloaded 27 October 2026

Source (add the link to where you downloaded the Transfermarkt dataset)

### Files used

 File  Contents  Origin 
---------
 `players.csv`  All players  Downloaded as is 
 `clubs.csv`  All clubs  Downloaded as is 
 `transfers.csv`  All transfers  Downloaded as is 
 `games_pl_2022_2025.csv`  Premier League games, 202223 to 202526  Filtered with pandas 
 `appearances_mufc_bha_2022_2025.csv`  Player appearances for Manchester United and Brighton  Filtered with pandas 
 `player_valuations_filtered.csv`  Player market valuations  Filtered with pandas 

### Filtering
The three filtered files were produced from the full Transfermarkt dataset by a pandas script, `pythonfilter_data.py`.

Filter rules
- Games (state the rule, for example competition ID GB1 and seasons 2022 to 2025)
- Appearances (state the rule, for example only games in the filtered games file and only Manchester United and Brighton players)
- Valuations (state the rule, for example only players found in the filtered appearances file)

## FBref
Downloaded (to be added)

Not yet collected. This section will be completed in the FBref phase.

## Reproducing the inputs
1. Download the Transfermarkt files from the source above and place them in `dataraw`.
2. Install the requirements `pip install -r requirements.txt`
3. Run `pythonfilter_data.py` to create the three filtered files.
4. Run the SQL scripts in `sql` in numeric order.