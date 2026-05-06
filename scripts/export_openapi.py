import json
import os
import sys
from pathlib import Path

# Add project root to sys.path
project_root = Path(__file__).parent.parent
sys.path.append(str(project_root))

from main import app

def export_openapi():
    schema = app.openapi()
    output_path = os.path.join(project_root, "openapi.json")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(schema, f, indent=2)
    print(f"OpenAPI schema exported to {output_path}")

if __name__ == "__main__":
    export_openapi()
