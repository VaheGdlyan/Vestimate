# Vestimate API

**Vestimate** is an AI-powered wardrobe assistant and recommendation engine. It ingests garment images, automatically segments backgrounds, embeds semantic properties using domain-specific models (FashionCLIP), and serves personalized outfit recommendations based on the user's local weather and daily schedule (via Google Calendar OAuth).

## Features
- **Wardrobe Ingestion Pipeline**: Asynchronous background removal and metadata extraction (segmentation and tagging).
- **Context-Aware Recommendations**: Aggregates weather and calendar events to serve situationally appropriate outfits.
- **LLM Selection**: Employs an LLM to heuristically select garments from the candidate pool and provide styling notes.
- **Caching & Pre-warming**: Recommendations are cached in Redis and pre-generated via Celery for fast response times.

---

## Local Setup

### 1. Requirements
- Python 3.11+
- Docker and Docker Compose (for PostgreSQL/Supabase & Redis)
- Access to Modal (for ML inference) and Cloudflare R2 (for asset storage)

### 2. Environment Variables
Create a `.env` file in the root directory based on the configuration required by `app/core/config.py`. Minimum required variables include:
```ini
SUPABASE_DATABASE_URL="postgresql+asyncpg://postgres:postgres@127.0.0.1:5432/postgres"
REDIS_URL="redis://127.0.0.1:6379/0"
TOKEN_ENCRYPTION_KEY="..."
# Plus Google OAuth, OpenAI, Modal, and R2 credentials
```

### 3. Virtual Environment
Create and activate your Python virtual environment, then install the dependencies:
```bash
python -m venv venv

# Windows
venv\Scripts\activate

# macOS/Linux
source venv/bin/activate

pip install -r requirements.txt
```

### 4. Start Infrastructure
Run the required services (Redis, PostgreSQL) locally via Docker Compose:
```bash
docker-compose up -d
```

### 5. Run Database Migrations
Initialize the database schema using the migration runner script:
```bash
python scripts/run_migrations.py
```

---

## Running the Application

### Start the FastAPI Server
Run the API using `uvicorn`:
```bash
uvicorn main:app --reload
```
The API will be available at `http://127.0.0.1:8000`. You can access the auto-generated Swagger UI documentation at `http://127.0.0.1:8000/docs`.

### Start the Celery Worker
In a separate terminal window (with your virtual environment activated), start the Celery worker to process background ingestion tasks and pre-warm recommendations:
```bash
celery -A app.worker.celery_app worker --loglevel=info
```

### Start the Celery Beat Scheduler
For periodic tasks (like cache eviction and pre-warming), start the celery beat scheduler:
```bash
celery -A app.worker.celery_app beat --loglevel=info
```
