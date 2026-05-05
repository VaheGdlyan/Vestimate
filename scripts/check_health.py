import httpx

try:
    r = httpx.get("http://localhost:8000/health", timeout=5.0)
    print(f"Status: {r.status_code}")
    print(f"Response: {r.text}")
except Exception as e:
    print(f"Error connecting: {e}")
