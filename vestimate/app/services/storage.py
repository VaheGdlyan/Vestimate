import asyncio
import boto3
from botocore.config import Config
from fastapi import UploadFile
from app.core.config import settings

def get_s3_client():
    """Initializes and returns a boto3 S3 client configured for Cloudflare R2."""
    if not settings.R2_ACCOUNT_ID:
        raise ValueError("R2_ACCOUNT_ID is not set in the environment variables.")

    r2_endpoint = f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
    return boto3.client(
        "s3",
        endpoint_url=r2_endpoint,
        aws_access_key_id=settings.R2_ACCESS_KEY_ID,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
        region_name="auto",
        config=Config(signature_version="s3v4"),
    )

async def save_upload_file(upload_file: UploadFile, user_id: str, filename: str) -> str:
    """
    Streams an uploaded file directly to Cloudflare R2 without keeping it in memory.
    Saves to the 'raw-uploads' path.
    """
    s3_client = get_s3_client()
    
    # Define bucket structure
    object_key = f"raw-uploads/{user_id}/{filename}"
    
    # Read file contents safely in async context
    file_bytes = await upload_file.read()
    
    # We use asyncio.to_thread to run the synchronous boto3 call
    await asyncio.to_thread(
        s3_client.put_object,
        Bucket=settings.R2_BUCKET_NAME,
        Key=object_key,
        Body=file_bytes,
        ContentType=upload_file.content_type or "image/jpeg"
    )
    
    return object_key

def generate_signed_url(object_key: str, expiry_seconds: int = 3600) -> str:
    """Generate a time-limited presigned GET URL for a private R2 object."""
    s3_client = get_s3_client()
    url = s3_client.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.R2_BUCKET_NAME, "Key": object_key},
        ExpiresIn=expiry_seconds
    )
    return url

