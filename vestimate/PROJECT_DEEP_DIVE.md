# VESTIMATE: PROJECT DEEP DIVE
**Generated for Architectural Analysis & LLM Handoff**
**Date:** Current State

This document outlines the exact current state and connective tissue of the Vestimate architecture, focusing strictly on the integration between the FastAPI backend and Flutter/Riverpod frontend.

---

## 1. The Data Contract (Backend-to-Frontend)

The application currently relies on a "Real-Image Mode" backend (`main.py`) which serves local images and bypasses the database to unblock UI development. 

### Model Mapping
*   **Wardrobe Items**:
    *   **Backend (FastAPI)**: Returns an inline dictionary: `{"id": str, "segmented_image_url": str, "category": str, "status": str, "metadata": dict}`.
    *   **Frontend (Dart)**: `WardrobeItem.fromJson` successfully maps this by looking for `json['segmented_image_url'] ?? json['raw_image_url']`. 
    *   **Status**: *Perfect Match.*
*   **Recommendations**:
    *   **Backend (FastAPI)**: Returns `{"item_ids": [str], "stylist_notes": str}`.
    *   **Frontend (Dart)**: `RecommendationState` extracts `item_ids` and `stylist_notes`, and cross-references the IDs against the local Riverpod `wardrobeProvider` to hydrate the full items.
    *   **Status**: *Perfect Match.*

### API Route Mapping
| Feature | Frontend (Dio) | Backend (FastAPI) | Status |
| :--- | :--- | :--- | :--- |
| **Fetch Wardrobe** | `GET /wardrobe/items` | `@app.get("/v1/wardrobe/items")` | Connected |
| **Recommendation** | `GET /recommendations/today` | `@app.get("/v1/recommendations/today")` | Connected |
| **Feedback** | `POST /feedback` | `@app.post("/v1/feedback")` | Connected (Prints to terminal) |
| **Upload Garment** | `POST /wardrobe/upload` | Missing in `main.py` | Broken/Unused |
| **Task Polling** | `GET /tasks/{taskId}` | Missing in `main.py` | Broken/Unused |

---

## 2. Reactive State Architecture (Riverpod 3.0)

We are utilizing `@riverpod` annotations (Riverpod 3.0 generation).

### Active Providers
*   `dioProvider`: **Data Source:** `AppConfig.apiBaseUrl` + Supabase interceptors. **Consumer:** All Repositories.
*   `authRepositoryProvider`: **Data Source:** Supabase SDK. **Consumer:** `LoginScreen`.
*   `wardrobeRepositoryProvider`: **Data Source:** `dioProvider`. **Consumer:** Data Notifiers.
*   `wardrobeCategoryFilterProvider`: **Data Source:** String state. **Consumer:** `WardrobeGalleryScreen`, `Wardrobe` (Notifier).
*   `wardrobeProvider` (AsyncNotifier): **Data Source:** `wardrobeRepositoryProvider.fetchWardrobeItems`. **Consumer:** `WardrobeGalleryScreen`, `todayRecommendation`.
*   `todayRecommendation` (FutureProvider): **Data Source:** `wardrobeRepositoryProvider.getTodayRecommendation`. **Consumer:** `WardrobeGalleryScreen` (via `RecommendationCard`).

### "Dead End" Providers
*   `filteredWardrobeProvider`: Exists in `wardrobe_notifier.dart` but is unused because `WardrobeGalleryScreen` now reads directly from `wardrobeProvider` (which filters server-side).
*   `TaskPolling`: Exists in `task_polling_provider.dart` to poll background segmentation tasks, but is entirely disconnected as there is no UI trigger to initiate an upload.

---

## 3. Component 'Logic Readiness' Audit

File-by-file audit of the `lib/features/**/presentation` layer.

*   **`LoginScreen` (`login_screen.dart`)**
    *   `ENTER WARDROBE` Button: **LOGIC ATTACHED** (Calls `_signIn` -> Supabase Auth).
    *   `CREATE ACCOUNT` Button: **LOGIC ATTACHED** (Calls `_signUp` -> Supabase Auth).
*   **`WardrobeGalleryScreen` (`wardrobe_gallery_screen.dart`)**
    *   Category Filter Chips: **LOGIC ATTACHED** (Updates `wardrobeCategoryFilterProvider`).
*   **`RecommendationCard` (`recommendation_card.dart`)**
    *   `WORN TODAY` Button: **LOGIC ATTACHED** (Sends POST to `/feedback`, invalidates provider).
    *   `SKIPPED` Button: **LOGIC ATTACHED** (Sends POST to `/feedback`, invalidates provider).
*   **`GarmentCard` (`garment_card.dart`)**
    *   Card Tap (`onTap`): **STUBBED** (Shows SnackBar "VIEWING ITEM DETAILS...", Detail screen does not exist).
*   **Missing Core UI Elements**
    *   **Upload Button**: **STUBBED/MISSING**. There is no Floating Action Button or trigger to activate the `WardrobeRepository.uploadGarment` method.

---

## 4. Local Persistence & Cache (Hive)

Hive is used for offline support and rapid re-rendering.

*   **Caching Strategy**: In `wardrobe_repository.dart`, when fetching the full wardrobe (`category == null`), the entire `List<Map<String, dynamic>>` response is written to `Hive.box('wardrobe_cache')` under the key `items`.
*   **Fallback Logic**: If the Dio `GET` request fails (e.g., connection timeout), the repository catches the error and returns the cached `items` list.
*   **Sync Logic**: There is **no background sync or diffing**. The cache is simply overwritten entirely upon every successful API fetch. There is no offline-mutation queuing (e.g., you cannot "Skip" an outfit while offline and have it sync later).

---

## 5. The "Vestimate" Core Loop

### Current Working Flow
1. **Load**: App opens -> `wardrobeProvider` triggers.
2. **Fetch**: `Dio` makes a `GET /wardrobe/items` request.
3. **Backend Processing**: FastAPI reads the local `test_images2` folder, assigns fake UUIDs, and returns the list.
4. **Recommendation**: `todayRecommendationProvider` fetches `GET /recommendations/today`. FastAPI selects random items from the folder and returns their IDs.
5. **Render**: Riverpod matches the IDs to the cached wardrobe items and renders the `RecommendationCard`.
6. **Feedback**: User taps "SKIPPED". Flutter sends `POST /v1/feedback`. Backend prints to terminal. Flutter invalidates `todayRecommendationProvider`, forcing Step 4 to repeat for a new outfit.

### Where the Loop is Broken / Stubbed
*   **LLM/AI Engine Disconnected**: The true AI engine (`pgvector`, GPT-4o-mini, Weather APIs) defined in `app/models/recommendation_schemas.py` is bypassed. The `main.py` simply returns `random.choice()`.
*   **Database Disconnected**: The `asyncpg` Supabase database layer is currently disconnected in `main.py` to prevent crashes during UI development.
*   **The Ingestion Pipeline**: The process of uploading an image, sending it to Celery/Modal for background removal, and polling for completion is fully written in the backend and frontend repositories, but **the UI to trigger it does not exist**.
