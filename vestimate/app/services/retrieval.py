"""
Retrieval Service — Category-Split pgvector Candidate Retrieval

Executes three parallel cosine similarity queries against the
wardrobe_items table — one per required outfit category (top,
bottom, shoes). Returns up to 5 candidates per category.

Uses raw SQL via asyncpg for the vector similarity operator (<=>).
"""

import asyncpg
from app.core.config import settings
from app.models.recommendation_schemas import GarmentCandidate, CandidateSet

CATEGORIES = ["top", "bottom", "shoes"]
CANDIDATES_PER_CATEGORY = 5
RECENCY_DAYS = 7


async def _get_db_connection() -> asyncpg.Connection:
    """Creates a single-use asyncpg connection for a query."""
    # asyncpg.connect() needs plain postgresql://, not postgresql+asyncpg://
    dsn = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    return await asyncpg.connect(dsn)


async def get_candidates(
    user_id: str,
    query_vector: list[float],
) -> CandidateSet:
    """
    Retrieves outfit candidates from pgvector for all three categories.
    Falls back to recency-based ordering if no vector results found.
    """
    vec_str = "[" + ",".join(str(v) for v in query_vector) + "]"

    results: dict[str, list[GarmentCandidate]] = {
        "top": [], "bottom": [], "shoes": []
    }

    conn = await _get_db_connection()
    try:
        for category in CATEGORIES:
            rows = await conn.fetch(
                f"""
                SELECT id, image_url, category, material, fit, colors
                FROM wardrobe_items
                WHERE user_id = $1
                  AND status = 'active'
                  AND category = $2
                  AND (
                    last_worn_at IS NULL
                    OR last_worn_at < NOW() - INTERVAL '{RECENCY_DAYS} days'
                  )
                ORDER BY embedding <=> $3::vector
                LIMIT {CANDIDATES_PER_CATEGORY}
                """,
                user_id,
                category,
                vec_str,
            )

            if not rows:
                rows = await conn.fetch(
                    f"""
                    SELECT id, image_url, category, material, fit, colors
                    FROM wardrobe_items
                    WHERE user_id = $1
                      AND status = 'active'
                      AND category = $2
                    ORDER BY last_worn_at DESC NULLS LAST
                    LIMIT {CANDIDATES_PER_CATEGORY}
                    """,
                    user_id,
                    category,
                )

            for row in rows:
                results[category].append(
                    GarmentCandidate(
                        id=str(row["id"]),
                        image_url=row["image_url"],
                        category=row["category"],
                        material=row["material"],
                        fit=row["fit"],
                        colors=list(row["colors"]) if row["colors"] else [],
                    )
                )

    finally:
        await conn.close()

    return CandidateSet(
        tops=results["top"],
        bottoms=results["bottom"],
        shoes=results["shoes"],
    )


def has_sufficient_candidates(candidates: CandidateSet) -> bool:
    """Returns True only if all three categories have at least 1 candidate."""
    return (
        len(candidates.tops) > 0
        and len(candidates.bottoms) > 0
        and len(candidates.shoes) > 0
    )
