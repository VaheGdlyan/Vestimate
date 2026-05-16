# VESTIMATE — Frontend Development Roadmap

**Role:** Lead Mobile Architect & Technical Project Manager  
**Project:** Vestimate Mobile (iOS & Android)  
**Version:** 1.0.0  
**Stack:** Flutter (Impeller), Riverpod 3.0, Dio 6.0, Hive (CE), Rive  

---

## 1. Executive Summary
This roadmap outlines the systematic construction of the Vestimate mobile frontend. Our primary objective is to deliver a premium, high-performance experience that manages the complex asynchronous lifecycle of AI-driven wardrobe digitization and recommendation. The development is synchronized with the existing FastAPI + Celery + Supabase backend.

---

## 2. The 3-Stage Communication Cycle
The core of the Vestimate experience is the **Ingestion Pipeline**. Every feature must adhere to this state machine:

1.  **Ingestion (Stage 1):** App captures/selects imagery and sends a multipart request via Dio. Backend responds with `task_id`.
2.  **Active Polling (Stage 2):** The UI switches to a Rive-driven "Processing" state. The app polls `GET /v1/tasks/{task_id}` every 2 seconds.
3.  **State Injection (Stage 3):** Upon task completion, Riverpod invalidates relevant providers and injects the new metadata and segmented image into the user's wardrobe.

---

## 4. Implementation Phases

### Phase 1: Initialization & Architecture (Day 1-2)
**Goal:** Establish the "Golden Stack" foundation and core state management patterns.

*   **Tasks:**
    *   Initialize Flutter project with Impeller enabled for 120Hz performance.
    *   Configure Riverpod 3.0 (Generator-based) as the primary state engine.
    *   Define Design Tokens: HSL-based color palette, Typography (Outfit/Inter), and premium spacing scales.
    *   Implement high-level App Router (GoRouter) and basic folder structure (`features/`, `core/`, `shared/`).
*   **Primary Packages:** `flutter_riverpod`, `riverpod_annotation`, `go_router`.
*   **Backend Sync:** None (Internal config).

### Phase 2: Core Networking & Authentication (Day 3-4)
**Goal:** Build a robust communication layer with the FastAPI gateway.

*   **Tasks:**
    *   Configure Dio 6.0 client with `BaseOptions` for the local/production API.
    *   Implement **AuthInterceptor**: Automatic injection of Supabase JWT into every request.
    *   Build **ErrorInterceptor**: Centralized handling of 401 (token refresh), 429 (rate limiting), and 503 (server maintenance).
    *   Integrate Supabase Flutter SDK for Auth flows (Google OAuth / Email).
*   **Primary Packages:** `dio`, `supabase_flutter`, `flutter_secure_storage`.
*   **Backend Endpoints:** `GET /v1/users/me/google-oauth`, `GET /health`.

### Phase 3: The AI Processing Lifecycle (Day 5-7)
**Goal:** Implement the "3-Stage Communication Cycle" for wardrobe ingestion.

*   **Tasks:**
    *   Build the `WardrobeRepository` for multipart image uploads.
    *   Implement the **Rive Controller**: A state-machine driven animation that reflects "Preprocessing" vs. "Success" vs. "Error".
    *   Develop the **Polling Provider**: A Riverpod `StreamProvider` that manages the `GET /v1/tasks/{task_id}` loop.
    *   Implement "State Injection" logic: Automatically updating the local Wardrobe State when a task hits `complete`.
*   **Primary Packages:** `rive`, `dio` (FormData), `riverpod`.
*   **Backend Endpoints:** `POST /v1/wardrobe/upload`, `GET /v1/tasks/{task_id}`.

### Phase 4: UI/UX & High-Performance Grids (Day 8-10)
**Goal:** Create a luxury viewing experience for digitized garments.

*   **Tasks:**
    *   Develop the **Segmented Garment Gallery**: A custom scroll-view optimized for PNGs with alpha channels.
    *   **Custom Painters:** Implement pixel-perfect grid layouts that ensure no image distortion during rendering.
    *   Build Wardrobe Filtering: Category-based filtering (Top, Bottom, Shoes) using Riverpod selectors.
    *   Implement "Pull-to-Prewarm": Triggering background pre-generation of recommendations.
*   **Primary Packages:** `cached_network_image`, `flutter_staggered_grid_view`.
*   **Backend Endpoints:** `GET /v1/wardrobe/items`.

### Phase 5: Recommendations & Offline Resilience (Day 11-14)
**Goal:** Deliver the final AI product and ensure stability without connectivity.

*   **Tasks:**
    *   Build the **Recommendation Card**: An interactive UI for "Today's Outfit" with Stylist Notes.
    *   Implement **Hive (CE) Persistence**: Local caching of wardrobe metadata to ensure instant load times.
    *   Integrate **Feedback Loop**: Sending "Worn Today" or "Skipped" actions back to the server.
    *   Final Polish: Micro-animations for page transitions and haptic feedback on action triggers.
*   **Primary Packages:** `hive_ce`, `path_provider`, `flutter_haptic`.
*   **Backend Endpoints:** `GET /v1/recommendations/today`, `POST /v1/feedback`.

---

## 5. Definition of Done (Frontend Gate)
*   [ ] App starts in < 2 seconds.
*   [ ] Image upload → Polling → Completion flow is seamless and animated via Rive.
*   [ ] Wardrobe grid maintains 60/120 FPS during heavy scrolling (Impeller).
*   [ ] Offline mode allows viewing previously ingested items.
*   [ ] JWT token refresh is handled transparently by Dio interceptors.
