import asyncio
import os
import httpx
from rich.console import Console
from rich.progress import track

console = Console()

API_URL = "http://127.0.0.1:8000/v1"
HEADERS = {"Authorization": "Bearer debug-token-123"}
TEST_IMAGES_DIR = "test_images"

async def upload_image(client: httpx.AsyncClient, filepath: str):
    filename = os.path.basename(filepath)
    ext = os.path.splitext(filename)[1].lower()
    
    content_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
        ".gif": "image/gif",
    }
    content_type = content_types.get(ext, "application/octet-stream")

    with open(filepath, "rb") as f:
        files = {"file": (filename, f, content_type)}
        response = await client.post(f"{API_URL}/wardrobe/upload", files=files, headers=HEADERS)
        
    response.raise_for_status()
    return response.json()

async def poll_task(client: httpx.AsyncClient, task_id: str, filename: str):
    max_retries = 30
    for _ in range(max_retries):
        resp = await client.get(f"{API_URL}/tasks/{task_id}", headers=HEADERS)
        resp.raise_for_status()
        status = resp.json().get("status")
        
        if status == "complete":
            return True
        elif status == "failed":
            console.print(f"[red]Failed to process {filename}[/red]")
            return False
            
        await asyncio.sleep(2)
        
    console.print(f"[red]Timeout waiting for {filename} to process[/red]")
    return False

async def main():
    console.print("[bold cyan]Starting Automated Vestimate Test...[/bold cyan]\n")
    
    if not os.path.exists(TEST_IMAGES_DIR):
        console.print(f"[red]Error: {TEST_IMAGES_DIR} directory not found![/red]")
        return
        
    image_files = [
        os.path.join(TEST_IMAGES_DIR, f) 
        for f in os.listdir(TEST_IMAGES_DIR) 
        if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp'))
    ]
    
    if not image_files:
        console.print(f"[red]No images found in {TEST_IMAGES_DIR}![/red]")
        return
        
    console.print(f"Found {len(image_files)} test images. Uploading to pipeline...\n")
    
    tasks = []
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Upload all images
        for filepath in image_files:
            filename = os.path.basename(filepath)
            console.print(f"Uploading [yellow]{filename}[/yellow]...")
            try:
                result = await upload_image(client, filepath)
                tasks.append((result["task_id"], filename))
            except Exception as e:
                console.print(f"[red]Failed to upload {filename}: {e}[/red]")
                
        if not tasks:
            console.print("[red]All uploads failed. Aborting test.[/red]")
            return
            
        console.print("\n[bold cyan]Waiting for ML Pipeline to segment and tag images...[/bold cyan]")
        
        # Poll all tasks
        for task_id, filename in track(tasks, description="Processing ML Jobs..."):
            await poll_task(client, task_id, filename)
            
        console.print("\n[bold green]✓ Wardrobe fully ingested![/bold green]\n")
        
        console.print("[bold cyan]Fetching AI Outfit Recommendation for Today...[/bold cyan]")
        
        try:
            # Force cache busting or just fetch
            resp = await client.get(f"{API_URL}/recommendations/today", headers=HEADERS, timeout=60.0)
            resp.raise_for_status()
            outfit = resp.json()
            
            console.print("\n[bold magenta]✨ YOUR AI STYLIST RECOMMENDATION ✨[/bold magenta]")
            console.print(f"[cyan]Weather Snapshot:[/cyan] {outfit['weather_snapshot']}")
            console.print(f"[cyan]Event Context:[/cyan] {outfit['events_summary']}")
            console.print("\n[bold]Selected Outfit:[/bold]")
            
            if outfit.get('top'):
                console.print(f"👕 Top: {outfit['top'].get('category')} ({', '.join(outfit['top'].get('colors', []))})")
            if outfit.get('bottom'):
                console.print(f"👖 Bottom: {outfit['bottom'].get('category')} ({', '.join(outfit['bottom'].get('colors', []))})")
            if outfit.get('shoes'):
                console.print(f"👟 Shoes: {outfit['shoes'].get('category')} ({', '.join(outfit['shoes'].get('colors', []))})")
                
            console.print(f"\n[green]Stylist Note:[/green] {outfit['stylist_note']}")
            
        except httpx.HTTPStatusError as e:
            console.print(f"[red]API Error:[/red] {e.response.status_code}")
            console.print(e.response.json())
        except Exception as e:
            console.print(f"[red]Failed to get recommendation: {e}[/red]")

if __name__ == "__main__":
    asyncio.run(main())
