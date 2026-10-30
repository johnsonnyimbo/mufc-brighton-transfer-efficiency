
from pathlib import Path
import re
import pandas as pd

BASE = Path(__file__).resolve().parent
RAW = BASE / "data" / "raw"
OUT = BASE / "output"

RAW.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

# Map common FBref column labels to consistent names.
ALIASES = {
    "player": "player",
    "squad": "club",
    "team": "club",
    "season": "season",
    "pos": "position",
    "position": "position",
    "age": "age",
    "mp": "matches_played",
    "matches": "matches_played",
    "starts": "starts",
    "min": "minutes",
    "minutes": "minutes",
    "gls": "goals",
    "goals": "goals",
    "ast": "assists",
    "assists": "assists",
    "crdy": "yellow_cards",
    "crdr": "red_cards",
    "sh": "shots",
    "sot": "shots_on_target",
    "save%": "save_percentage",
    "cs": "clean_sheets",
}

KEYS = ["player", "club", "season"]


def clean_column_name(column):
    """Flatten and normalize CSV column headers."""
    if isinstance(column, tuple):
        column = "_".join(str(x) for x in column if str(x) != "nan")

    column = str(column).strip().lower()
    column = re.sub(r"[\s%]+", "_", column)
    column = re.sub(r"[^a-z0-9_]", "", column)
    return column.strip("_")


def get_season(filename):
    match = re.search(
        r"(20\d{2})[-_](\d{2,4})",
        filename
    )
    if not match:
        return None

    start = int(match.group(1))
    end = match.group(2)

    if len(end) == 2:
        end = str(start // 100 * 100 + int(end))
    return f"{start}-{end}"


def get_category(filename):
    name = filename.lower()
    categories = [
        "playing_time",
        "standard",
        "shooting",
        "passing",
        "defense",
        "keeper",
        "misc",
    ]

    for category in categories:
        if category in name:
            return category

    return "other"


def load_csv(path):
    season = get_season(path.name)

    if not season:
        print(f"SKIP: Cannot identify season: {path.name}")
        return None

    try:
        df = pd.read_csv(path)
    except Exception as exc:
        print(f"ERROR reading {path.name}: {exc}")
        return None

    df.columns = [clean_column_name(c) for c in df.columns]

    # Remove repeated header rows occasionally found in exports.
    if "player" in df.columns:
        df = df[
            df["player"].notna()
            & (df["player"].astype(str).str.lower() != "player")
        ].copy()
    else:
        print(f"SKIP: No player column in {path.name}")
        return None

    rename = {}
    for col in df.columns:
        # Match known names and common prefixes.
        if col in ALIASES:
            rename[col] = ALIASES[col]
        elif col.startswith("min_"):
            rename[col] = "minutes_" + col[4:]

    df = df.rename(columns=rename)

    if "club" not in df.columns:
        print(f"SKIP: No team column in {path.name}")
        return None

    df["season"] = season
    df["source_file"] = path.name
    df["table_category"] = get_category(path.name)

    for key in KEYS:
        if key not in df.columns:
            print(f"SKIP: Missing key {key} in {path.name}")
            return None

    df["player"] = df["player"].astype(str).str.strip()
    df["club"] = df["club"].astype(str).str.strip()

    return df


def main():
    files = sorted(RAW.glob("*.csv"))

    if not files:
        print(f"No CSV files found in: {RAW}")
        print("Add permitted FBref CSV exports and run again.")
        return

    tables = []
    for path in files:
        df = load_csv(path)
        if df is not None:
            tables.append(df)
            print(f"Loaded {path.name}: {len(df)} rows")

    if not tables:
        print("No usable tables found. Check column headers.")
        return

    # Save the combined source records before joining tables.
    raw_combined = pd.concat(tables, ignore_index=True, sort=False)
    raw_combined.to_csv(
        OUT / "all_source_records.csv", index=False
    )

    # Join different statistic tables by player, club and season.
    merged = None

    for df in tables:
        category = df["table_category"].iloc[0]

        # Avoid collisions between statistics from different tables.
        payload = df.drop(
            columns=["source_file", "table_category"],
            errors="ignore"
        ).copy()

        payload = payload.rename(columns={
            c: f"{category}_{c}"
            for c in payload.columns
            if c not in KEYS
        })

        # Each table must have at most one row per player/club/season.
        duplicates = payload.duplicated(KEYS, keep=False)
        if duplicates.any():
            print(
                f"WARNING: Duplicate player keys in "
                f"{category}. Keeping first row."
            )
            payload = payload.drop_duplicates(KEYS, keep="first")

        if merged is None:
            merged = payload
        else:
            # Only merge if this table adds new columns.
            new_cols = [
                c for c in payload.columns
                if c in KEYS or c not in merged.columns
            ]
            payload = payload[new_cols]
            merged = merged.merge(
                payload,
                on=KEYS,
                how="outer",
                validate="one_to_one"
            )

    # Remove rows that are not Premier League player records.
    # Club names are preserved as supplied by the source.
    merged.to_csv(OUT / "premier_league_all.csv", index=False)

    def club_match(series, club):
        text = series.fillna("").str.lower().str.strip()
        return text.str.contains(club, regex=False)

    man_utd = merged[club_match(merged["club"], "manchester utd")]
    brighton = merged[
        club_match(merged["club"], "brighton")
    ]

    man_utd.to_csv(OUT / "manchester_united.csv", index=False)
    brighton.to_csv(OUT / "brighton.csv", index=False)

    # Data quality report.
    report = pd.DataFrame({
        "column": merged.columns,
        "missing_rows": merged.isna().sum().values,
        "missing_percent": (
            merged.isna().mean().values * 100
        ).round(2),
    })

    report.to_csv(OUT / "data_quality_report.csv", index=False)

    print("\nCollection and consolidation complete.")
    print(f"All records: {len(merged)}")
    print(f"Manchester United: {len(man_utd)}")
    print(f"Brighton: {len(brighton)}")
    print(f"Output folder: {OUT}")


if __name__ == "__main__":
    main()
