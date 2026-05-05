import sys
import os
import sentry_sdk

# Add the project root to sys.path
sys.path.append(os.getcwd())

from app.core.config import settings
from app.core.observability import init_sentry

def test():
    print(f"SENTRY_DSN: {settings.SENTRY_DSN}")
    if not settings.SENTRY_DSN or "your-sentry-dsn" in settings.SENTRY_DSN:
        print("SENTRY_DSN is placeholder or empty. Live capture skipped.")
        # We can still test if the sdk is importable and logic works
        init_sentry()
        print("init_sentry() called (should log warning if DSN missing)")
    else:
        init_sentry()
        print("Sending test message to Sentry...")
        event_id = sentry_sdk.capture_message("Vestimate Phase 4 Live Test")
        print(f"Message sent. Event ID: {event_id}")

if __name__ == "__main__":
    test()
