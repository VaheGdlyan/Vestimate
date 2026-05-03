import httpx
import logging
import asyncio
import json
from app.worker.celery_app import celery_app
from app.services.storage import get_s3_client
from app.core.config import settings

logger = logging.getLogger(__name__)


@celery_app.task(name="ingest_garment", bind=True, max_retries=3)
def ingest_garment(self, item_id: str, raw_object_key: str, user_id: str):
    """
    Full ML ingestion pipeline for a wardrobe item.
    
    Steps per architecture spec:
    1. Download image from R2 via presigned URL
    2. Call Modal: rembg background removal
    3. Upload segmented PNG back to R2
    4. Call Modal: FashionCLIP embed + tag
    5. Confidence gate (< 0.70 → needs_review)
    6. Color palette mapping (deterministic)
    7. Upsert embedding + metadata into Supabase (pgvector)
    8. Insert into manual_review_queue if needed
    9. Emit wardrobe.item.ingested event
    """
    s3_client = get_s3_client()
    
    # Read Modal endpoint URLs from config (populated via .env)
    modal_segment_url = settings.MODAL_ENDPOINT_SEGMENT
    modal_embed_url = settings.MODAL_ENDPOINT_EMBED
    
    if not modal_segment_url or not modal_embed_url:
        raise ValueError(
            "MODAL_ENDPOINT_SEGMENT and MODAL_ENDPOINT_EMBED must be set in .env. "
            "Deploy modal_inference.py first: `modal deploy app/worker/modal_inference.py`"
        )
    
    try:
        # Step 1: Generate a presigned URL to securely download the raw image from R2
        raw_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': settings.R2_BUCKET_NAME, 'Key': raw_object_key},
            ExpiresIn=300
        )
        
        # Step 2: Download raw bytes
        with httpx.Client(timeout=60.0) as client:
            raw_response = client.get(raw_url)
            raw_response.raise_for_status()
            raw_bytes = raw_response.content
            logger.info(f"[{item_id}] Downloaded {len(raw_bytes)} bytes from R2")
            
            # Custom retry loop to handle Modal's aggressive 429 rate limits
            def post_with_retry(url, content, timeout, max_attempts=7):
                import time
                for attempt in range(max_attempts):
                    resp = client.post(url, content=content, headers={"Content-Type": "application/octet-stream"}, timeout=timeout)
                    if resp.status_code == 429:
                        wait_time = 2 ** attempt
                        logger.warning(f"[{item_id}] 429 Too Many Requests. Retrying in {wait_time}s...")
                        time.sleep(wait_time)
                        continue
                    resp.raise_for_status()
                    return resp
                raise Exception(f"Max retries exceeded for {url} (429 Too Many Requests)")
            
            # Step 3: Call Modal Segmentation Endpoint (rembg)
            seg_response = post_with_retry(modal_segment_url, raw_bytes, 120.0)
            segmented_png_bytes = seg_response.content
            logger.info(f"[{item_id}] Segmentation complete: {len(segmented_png_bytes)} bytes")
            
            # Step 4: Upload Segmented PNG back to R2
            segmented_key = f"segmented/{user_id}/{item_id}.png"
            s3_client.put_object(
                Bucket=settings.R2_BUCKET_NAME,
                Key=segmented_key,
                Body=segmented_png_bytes,
                ContentType="image/png"
            )
            logger.info(f"[{item_id}] Segmented image uploaded to R2: {segmented_key}")
            
            # Step 5: Call Modal Embedding & Tagging Endpoint (FashionCLIP)
            embed_response = post_with_retry(modal_embed_url, segmented_png_bytes, 120.0)
            ml_results = embed_response.json()
            
            embedding = ml_results["embedding"]
            tags = ml_results["tags"]
            logger.info(f"[{item_id}] ML tags: category={tags['category']['value']} "
                       f"({tags['category']['confidence']:.3f})")
            
            # Step 6: Confidence Gate
            min_confidence = min(
                tags["category"]["confidence"],
                tags["fit"]["confidence"],
                tags["material"]["confidence"]
            )
            needs_review = min_confidence < 0.70
            
            # Step 7: Color Palette Mapping (deterministic, no GPU)
            # TODO: Implement full 32-color palette mapping
            colors = tags.get("colors", ["unknown"])
            if not isinstance(colors, list):
                colors = ["unknown"]
            
            # Step 8: Database Upsert — embedding + metadata into wardrobe_items
            def upsert_db():
                from supabase import create_client
                supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
                
                # Construct CDN URL for the segmented image
                image_url = f"https://cdn.vestimate.app/{segmented_key}"
                
                # Update the wardrobe_items row
                supabase.table("wardrobe_items").update({
                    "embedding": embedding,
                    "status": "active",
                    "category": tags["category"]["value"],
                    "material": tags["material"]["value"],
                    "fit": tags["fit"]["value"],
                    "colors": colors,
                    "confidence_min": min_confidence,
                    "needs_review": needs_review,
                    "image_url": image_url,
                }).eq("id", item_id).execute()
                
                # Step 8b: Insert into manual_review_queue if confidence is low
                if needs_review:
                    supabase.table("manual_review_queue").insert({
                        "item_id": item_id,
                        "user_id": user_id,
                        "tags_raw": tags
                    }).execute()
                    logger.info(f"[{item_id}] Low confidence ({min_confidence:.3f}), "
                               f"added to review queue")
                
                # Step 9: Emit wardrobe.item.ingested event
                supabase.table("event_log").insert({
                    "event_type": "wardrobe.item.ingested",
                    "user_id": user_id,
                    "payload": {
                        "item_id": item_id,
                        "category": tags["category"]["value"],
                        "confidence_min": min_confidence,
                        "needs_review": needs_review
                    }
                }).execute()
            
            upsert_db()
            
            logger.info(f"[{item_id}] Ingestion complete. "
                       f"Category: {tags['category']['value']}, "
                       f"Confidence: {min_confidence:.3f}, "
                       f"Review: {needs_review}")
            
            return {
                "item_id": item_id, 
                "status": "complete",
                "category": tags["category"]["value"],
                "confidence_min": min_confidence,
                "needs_review": needs_review,
                "message": "Successfully ingested, ML pipelines executed, and stored in Supabase."
            }
            
    except Exception as e:
        logger.error(f"Failed to ingest garment {item_id}: {str(e)}")
        
        # Update Supabase status to 'failed' so the client knows
        try:
            from supabase import create_client
            supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
            supabase.table("wardrobe_items").update({
                "status": "failed"
            }).eq("id", item_id).execute()
        except Exception as db_err:
            logger.error(f"Failed to mark item {item_id} as failed in DB: {db_err}")
        
        raise self.retry(exc=e, countdown=60, max_retries=3)

