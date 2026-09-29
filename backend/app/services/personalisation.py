"""Adaptive difficulty and activity recommendations (v1: explainable rules).

Pipeline: synced sessions -> per-game features -> level decision -> ranked
recommendations, each with a plain reason. Rules are deliberately transparent;
tree-based models (scikit-learn / XGBoost) can replace `decide_level` once there
is enough real data to train and validate them.
"""

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta

from ..models import Game, GameSession
from ..security import as_utc

WINDOW = 5  # most recent sessions per game used for the level decision


@dataclass
class GameFeatures:
    slug: str
    level: int
    sessions: int
    accuracy: float | None
    completion_rate: float | None
    avg_response_ms: float | None
    repeated_error_rate: float | None
    plays_7d: int


def extract_features(game: Game, sessions: list[GameSession], now: datetime) -> GameFeatures:
    mine = sorted((s for s in sessions if s.game_slug == game.slug and not s.deleted), key=lambda s: as_utc(s.started_at))
    recent = mine[-WINDOW:]
    trials = sum(s.trials for s in recent)
    timed = [s.avg_response_ms for s in recent if s.avg_response_ms is not None]
    week_ago = now - timedelta(days=7)
    return GameFeatures(
        slug=game.slug,
        level=recent[-1].level if recent else game.min_level,
        sessions=len(mine),
        accuracy=(sum(s.correct for s in recent) / trials) if trials else None,
        completion_rate=(sum(s.completed for s in recent) / len(recent)) if recent else None,
        avg_response_ms=(sum(timed) / len(timed)) if timed else None,
        repeated_error_rate=(sum(s.repeated_errors for s in recent) / trials) if trials else None,
        plays_7d=sum(1 for s in mine if as_utc(s.started_at) >= week_ago),
    )


def decide_level(f: GameFeatures, game: Game) -> tuple[int, str]:
    if f.sessions < 2 or f.accuracy is None:
        return f.level, "Getting to know how you play"
    if f.accuracy >= 0.85 and (f.completion_rate or 0) >= 0.9:
        if f.level < game.max_level:
            return f.level + 1, "Doing very well, so the next level is ready"
        return f.level, "Doing very well at the top level"
    if f.accuracy < 0.6 or (f.completion_rate or 0) < 0.5 or (f.repeated_error_rate or 0) > 0.3:
        if f.level > game.min_level:
            return f.level - 1, "Making it a little easier and more enjoyable"
        return f.level, "Practising at a comfortable level"
    return f.level, "Good practice at this level"


DOMAIN_ORDER = ["memory_recall", "routine", "attention", "language", "pattern", "speed"]


def recommend(games: list[Game], sessions: list[GameSession], now: datetime, top_n: int = 6) -> list[dict]:
    """Ranked list of {game_slug, level, rank, reason}. Favours variety across
    cognitive domains, then games played less this week."""
    rows = []
    domain_plays: dict[str, int] = defaultdict(int)
    feats = {}
    for g in games:
        f = extract_features(g, sessions, now)
        feats[g.slug] = f
        domain_plays[g.domain] += f.plays_7d
    for g in games:
        f = feats[g.slug]
        level, reason = decide_level(f, g)
        if f.sessions == 0:
            reason = "Something new to try"
        elif domain_plays[g.domain] == 0:
            reason = "Not played this week. " + reason
        domain_rank = DOMAIN_ORDER.index(g.domain) if g.domain in DOMAIN_ORDER else len(DOMAIN_ORDER)
        score = domain_plays[g.domain] * 10 + f.plays_7d * 3 + domain_rank
        rows.append((score, g.slug, level, reason))
    rows.sort()
    return [
        {"game_slug": slug, "level": level, "rank": i + 1, "reason": reason}
        for i, (_, slug, level, reason) in enumerate(rows[:top_n])
    ]
