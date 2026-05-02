import httpx
import logging
import asyncio
from app.worker.celery_app import celery_app
from app.services.storage import get_s3_client
from app.core.config import settings

logger = logging.getLogger(__name__)

# NOTE: You will get these URLs after running `modal deploy app.worker.modal_inference`
MODAL_SEGMENT_URL = "https://vahegdlyan--vestimate-inference-segment.modal.run"
MODAL_EMBED_URL = "https://vahegdlyan--vestimate-inference-embed-and-tag.modal.run"

@celery_app.task(name="ingest_garment", bind=True)
def ingest_garment(self, item_id: str, raw_object_key: str, user_id: str):
    s3_client = get_s3_client()
    
    try:
        # Step 1: Generate a presigned URL to securely download the raw image from R2
        raw_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': settings.R2_BUCKET_NAME, 'Key': raw_object_key},
            ExpiresIn=300
        )
        
        # Step 2: Download raw bytes
        with httpx.Client() as client:
            raw_response = client.get(raw_url)
            raw_response.raise_for_status()
            raw_bytes = raw_response.content
            
            # Step 3: Call Modal Segmentation Endpoint (rembg)
            seg_response = client.post(MODAL_SEGMENT_URL, content=raw_bytes)
            seg_response.raise_for_status()
            segmented_png_bytes = seg_response.content
            
            # Step 4: Upload Segmented PNG back to R2
            segmented_key = f"segmented/{user_id}/{item_id}.png"
            s3_client.put_object(
                Bucket=settings.R2_BUCKET_NAME,
                Key=segmented_key,
                Body=segmented_png_bytes,
                ContentType="image/png"
            )
            
            # Step 5: Call Modal Embedding & Tagging Endpoint (FashionCLIP)
            embed_response = client.post(MODAL_EMBED_URL, content=segmented_png_bytes)
            embed_response.raise_for_status()
            ml_results = embed_response.json()
            
            embedding = ml_results["embedding"]
            tags = ml_results["tags"]
            
            # Step 6: Confidence Gate
            min_confidence = min(
                tags["category"]["confidence"],
                tags["fit"]["confidence"],
                tags["material"]["confidence"]
            )
            needs_review = min_confidence < 0.70
            
            # (Step 7: Palette Mapping will go here - abstracted for now)
            colors = ["navy", "charcoal"] # Placeholder mapping
            
            # Step 8: The Bridge (Database Upsert)
            async def upsert_db():
                from sqlalchemy import text
                from app.core.config import async_session_maker
                
                # In production, use your actual Cloudflare CDN domain
                image_url = f"https://cdn.vestimate.app/{segmented_key}"
                
                async with async_session_maker() as session:
                    query = text("""
                        UPDATE wardrobe_items 
                        SET embedding = :embedding::vector(512),
                            status = 'active',
                            category = :category,
                            material = :material,
                            fit = :fit,
                            colors = :colors,
                            confidence_min = :confidence_min,
                            needs_review = :needs_review,
                            image_url = :image_url,
                            processed_at = NOW()
                        WHERE id = :item_id
                    """)
                    await session.execute(query, {
                        "embedding": str(embedding), # pgvector natively parses stringified lists
                        "category": tags["category"]["value"],
                        "material": tags["material"]["value"],
                        "fit": tags["fit"]["value"],
                        "colors": colors,
                        "confidence_min": min_confidence,
                        "needs_review": needs_review,
                        "image_url": image_url,
                        "item_id": item_id
                    })
                    await session.commit()
            
            # Run the async DB transaction from within the sync Celery worker
            asyncio.run(upsert_db())
            
            return {
                "item_id": item_id, 
                "status": "complete",
                "message": "Successfully ingested, ML pipelines executed, and safely stored in Supabase."
            }
            
    except Exception as e:
        logger.error(f"Failed to ingest garment {item_id}: {str(e)}")
        # In production, we'd update Supabase status to 'failed' here
        raise self.retry(exc=e, countdown=60, max_retries=3)
