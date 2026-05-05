import asyncio
import httpx
import time
from fastapi import FastAPI, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import uvicorn
from threading import Thread

# Create a minimal app to test the limiter logic
limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/test")
@limiter.limit("5/minute")
async def test_limit(request: Request):
    return {"status": "ok"}

def run_server():
    uvicorn.run(app, host="127.0.0.1", port=8001)

if __name__ == "__main__":
    t = Thread(target=run_server, daemon=True)
    t.start()
    time.sleep(2) # Wait for server
    
    print("Testing Rate Limit (5/min):")
    for i in range(1, 8):
        resp = httpx.get("http://127.0.0.1:8001/test")
        print(f"  Request {i}: {resp.status_code}")
        if resp.status_code == 429:
            print("  SUCCESS: 429 Rate Limit Exceeded detected.")
            break
    else:
        print("  FAIL: No 429 detected.")
