import os
import httpx
import asyncio
from pathlib import Path

# Change this to whatever you name your folder of images!
IMAGE_FOLDER = "test_images" 
USER_ID = "11111111-1111-1111-1111-111111111111"
API_URL = "http://127.0.0.1:8000/v1/wardrobe/upload"

async def upload_image(client: httpx.AsyncClient, file_path: Path):
    print(f"Uploading {file_path.name}...")
    try:
        with open(file_path, "rb") as f:
            files = {"file": (file_path.name, f, "image/jpeg")}
            data = {"user_id": USER_ID}
            
            response = await client.post(API_URL, data=data, files=files, timeout=60.0)
            
            if response.status_code in [200, 202]:
                print(f"✅ Success! {file_path.name} is processing.")
            else:
                print(f"❌ Failed {file_path.name}: {response.text}")
    except Exception as e:
        print(f"❌ Error uploading {file_path.name}: {e}")

async def main():
    folder = Path(IMAGE_FOLDER)
    if not folder.exists():
        print(f"Folder '{IMAGE_FOLDER}' not found. Please create it and add images.")
        return

    images = [p for p in folder.iterdir() if p.suffix.lower() in [".jpg", ".jpeg", ".png", ".webp"]]
    
    if not images:
        print(f"No images found in '{IMAGE_FOLDER}'.")
        return

    print(f"Found {len(images)} images. Starting upload...")
    
    async with httpx.AsyncClient() as client:
        # Upload one by one so we don't overwhelm your local PC
        for img_path in images:
            await upload_image(client, img_path)
            
    print("\n🎉 All uploads initiated! Check your terminal running the backend to see the Celery workers processing them.")

if __name__ == "__main__":
    asyncio.run(main())
