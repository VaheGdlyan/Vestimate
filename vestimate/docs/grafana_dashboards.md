# Vestimate Grafana Dashboards

## Dashboard 1: Recommendation Engine Health
Panels:
- Cache hit ratio (target: > 80%) — metric: ratio of requests with cache_hit=true
- p50 / p95 / p99 recommendation endpoint latency (ms)
- OpenAI API calls per hour (target: < 20% of total requests)
- Fallback recommendation rate (GPT unavailable events)

## Dashboard 2: Ingestion Pipeline
Panels:
- Celery task success rate (%) over time
- Celery task duration p50/p95 (seconds) — segment + embed separately
- Task queue depth (Redis LLEN celery)
- Failed items rate (status = 'failed' inserts per hour)
- Manual review queue depth (needs_review = true unreviewed)

## Dashboard 3: API Gateway
Panels:
- Total requests per minute (all endpoints)
- Error rate by endpoint (4xx, 5xx)
- Rate limit hits per user (429 responses)
- Authentication failures (401/403 count)

## Dashboard 4: Infrastructure
Panels:
- Railway API server memory/CPU
- Railway Celery worker memory/CPU
- Redis memory usage vs. maxmemory limit
- Modal invocations and cold start frequency

## Dashboard 5: Product Metrics (Alpha)
Panels:
- Daily active recommendations generated
- Feedback action breakdown (worn / skipped / saved) — pie chart
- Items ingested per day
- Users with 0 wardrobe items (stuck in onboarding)

## Dashboard 6: Cost Tracker
Panels:
- OpenAI token usage → estimated daily/monthly cost
- Modal GPU seconds consumed → cost
- R2 storage usage and egress
- Total estimated monthly cost gauge vs. $200 budget
