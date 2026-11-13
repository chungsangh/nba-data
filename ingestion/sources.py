"""Registry of upstream datasets published by sportsdataverse-data as GitHub release assets.

Each dataset is one GitHub release tag holding one parquet file per season. Season numbering follows
ESPN: the 2025-26 NBA season is season ``2026``.
"""

from __future__ import annotations

from dataclasses import dataclass

RELEASES_BASE_URL = "https://github.com/sportsdataverse/sportsdataverse-data/releases/download"


@dataclass(frozen=True)
class Dataset:
    """One upstream dataset and the raw table it lands in."""

    name: str  # raw table name in the warehouse
    release_tag: str  # GitHub release tag
    file_pattern: str  # parquet file name, formatted with the season

    def file_name(self, season: int) -> str:
        return self.file_pattern.format(season=season)

    def url(self, season: int) -> str:
        return f"{RELEASES_BASE_URL}/{self.release_tag}/{self.file_name(season)}"

    @property
    def timestamp_url(self) -> str:
        """Small JSON file the publisher rewrites on every refresh."""
        return f"{RELEASES_BASE_URL}/{self.release_tag}/timestamp.json"


DATASETS: dict[str, Dataset] = {
    d.name: d
    for d in [
        Dataset("espn_nba_plays", "espn_nba_pbp", "play_by_play_{season}.parquet"),
        Dataset("espn_nba_schedules", "espn_nba_schedules", "nba_schedule_{season}.parquet"),
        Dataset(
            "espn_nba_player_boxscores", "espn_nba_player_boxscores", "player_box_{season}.parquet"
        ),
        Dataset("espn_nba_team_boxscores", "espn_nba_team_boxscores", "team_box_{season}.parquet"),
        # Current roster per team; each daily load replaces it, and dbt's snap_players snapshot
        # keeps the history of roster moves.
        Dataset("espn_nba_rosters", "espn_nba_rosters", "rosters_{season}.parquet"),
    ]
}
