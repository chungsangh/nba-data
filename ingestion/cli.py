"""Command line entry point: ``uv run nba-ingest --seasons 2026 2027``."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import date

from ingestion.loader import ingest
from ingestion.sources import DATASETS

DEFAULT_DATABASE = "data/nba.duckdb"


def current_season(today: date | None = None) -> int:
    """ESPN season label for a date: the season starting in October is labelled by its end year."""
    today = today or date.today()
    return today.year + 1 if today.month >= 8 else today.year


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--seasons",
        type=int,
        nargs="+",
        default=None,
        help="ESPN season labels to load (2026 = the 2025-26 season). Default: current season.",
    )
    parser.add_argument(
        "--datasets",
        nargs="+",
        choices=sorted(DATASETS),
        default=sorted(DATASETS),
        help="Datasets to load. Default: all.",
    )
    parser.add_argument(
        "--database",
        default=os.environ.get("NBA_DUCKDB_PATH", DEFAULT_DATABASE),
        help="DuckDB path or MotherDuck string (md:<db>). Default: $NBA_DUCKDB_PATH or "
        f"{DEFAULT_DATABASE}.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_args(argv)
    seasons = args.seasons or [current_season()]
    if not args.database.startswith("md:"):
        os.makedirs(os.path.dirname(args.database) or ".", exist_ok=True)
    results = ingest([DATASETS[name] for name in args.datasets], seasons, args.database)
    if not results:
        logging.error("Nothing was loaded")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
