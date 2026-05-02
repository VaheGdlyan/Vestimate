import modal
from fastapi import Request, Response
from typing import Dict, Any

# Define the container images with required ML dependencies
image_rembg = modal.Image.debian_slim().pip_install("rembg[cli]==2.0.50", "Pillow==10.3.0", "numpy==1.26.4")
image_clip = modal.Image.debian_slim().pip_install("torch==2.3.0", "transformers==4.41.0", "Pillow==10.3.0", "fastapi[standard]")

app = modal.App("vestimate-inference")

@app.function(image=image_rembg, gpu="T4")
@modal.fastapi_endpoint(method="POST")
async def segment(request: Request) -> Response:
    """
    Endpoint: /inference/segment
    Accepts raw image bytes, applies U-2-Net background removal, and returns PNG bytes with alpha channel.
    """
    from rembg import remove
    
    # In a production scenario, you would parse the multipart/form-data.
    # For this architecture, we expect raw bytes in the body for speed.
    input_bytes = await request.body()
    output_bytes = remove(input_bytes)
    
    return Response(content=output_bytes, media_type="image/png")

@app.function(image=image_clip, gpu="T4")
@modal.fastapi_endpoint(method="POST")
async def embed_and_tag(request: Request) -> Dict[str, Any]:
    """
    Endpoint: /inference/embed_and_tag
    Accepts segmented PNG bytes, extracts a 512-dim embedding and tags using FashionCLIP (ViT-B/16).
    """
    import io
    from PIL import Image
    import torch
    from transformers import CLIPProcessor, CLIPModel
    
    # NOTE: In actual production, models should be pre-downloaded to the image 
    # using modal.Image...run_commands(...) to prevent cold-start downloads.
    # We use standard CLIP here as a stand-in for the domain-specific FashionCLIP.
    model_id = "openai/clip-vit-base-patch16"
    processor = CLIPProcessor.from_pretrained(model_id)
    model = CLIPModel.from_pretrained(model_id)
    
    image_bytes = await request.body()
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    
    # Define tag taxonomies
    candidate_categories = ["top", "bottom", "outerwear", "shoes", "accessory", "dress"]
    candidate_fits = ["slim", "relaxed", "regular", "oversized"]
    candidate_materials = ["cotton", "wool", "denim", "leather", "polyester", "silk"]
    
    # Process inputs for zero-shot classification & embedding
    inputs = processor(
        text=candidate_categories + candidate_fits + candidate_materials, 
        images=image, 
        return_tensors="pt", 
        padding=True
    )
    
    with torch.no_grad():
        outputs = model(**inputs)
        image_embeds = outputs.image_embeds
        logits_per_image = outputs.logits_per_image
        probs = logits_per_image.softmax(dim=1).squeeze().tolist()
        
    embedding = image_embeds.squeeze().tolist() # float[512]
    
    # We slice the probabilities corresponding to our candidate lists
    cat_probs = probs[:len(candidate_categories)]
    fit_probs = probs[len(candidate_categories):len(candidate_categories)+len(candidate_fits)]
    mat_probs = probs[-len(candidate_materials):]
    
    # Extract highest probability matches
    cat_max_idx = cat_probs.index(max(cat_probs))
    fit_max_idx = fit_probs.index(max(fit_probs))
    mat_max_idx = mat_probs.index(max(mat_probs))
    
    return {
        "embedding": embedding,
        "tags": {
            "category": {"value": candidate_categories[cat_max_idx], "confidence": round(cat_probs[cat_max_idx], 3)},
            "fit": {"value": candidate_fits[fit_max_idx], "confidence": round(fit_probs[fit_max_idx], 3)},
            "material": {"value": candidate_materials[mat_max_idx], "confidence": round(mat_probs[mat_max_idx], 3)}
        }
    }
