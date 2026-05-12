Phase 1 — Foundation & Unblocking
[ ] Task: Implement Multipart Wardrobe Upload Route

Target File(s): main.py

Action: Create POST /v1/wardrobe/upload endpoint using UploadFile. Implement logic to save the file temporarily, trigger the existing Celery/Modal background removal task, and return a JSON response containing the task_id. Mirror the response shape expected by wardrobeRepository.uploadGarment().

Acceptance Criteria: Endpoint returns a 200 OK with a valid task_id string when a multipart image is posted via Postman or cURL.

[ ] Task: Implement Task Status Polling Route

Target File(s): main.py

Action: Create GET /v1/tasks/{taskId} endpoint. Use the taskId to query the Celery/Modal task result. Return a JSON object containing status (e.g., 'pending', 'completed') and result (the processed image URL).

Acceptance Criteria: Endpoint returns the correct execution status and result payload for a known Celery task ID.

[ ] Task: Reconnect Database Layer with Graceful Degradation

Target File(s): main.py

Action: Re-enable the Supabase/asyncpg connection logic. Wrap initialization in a try/except block. If the connection fails, log a warning and set a global flag to allow the server to continue running in "local-image mode" using mock data.

Acceptance Criteria: Server starts successfully even if DB environment variables are missing, and connects successfully when they are present.

[ ] Task: Add Wardrobe Upload UI Trigger

Target File(s): lib/features/wardrobe/presentation/wardrobe_gallery_screen.dart

Action: Add a FloatingActionButton to the Scaffold. Inside onPressed, use ImagePicker to select a photo. Pass the file to ref.read(wardrobeRepositoryProvider).uploadGarment() and then call ref.read(taskPollingProvider.notifier).startPolling(taskId) with the resulting ID.

Acceptance Criteria: Tapping the FAB opens the system gallery, and selecting an image triggers the repository upload method.

[ ] Task: Wire TaskPollingProvider to UI and State

Target File(s): lib/features/wardrobe/state/task_polling_provider.dart, lib/features/wardrobe/presentation/wardrobe_gallery_screen.dart

Action: Ensure TaskPollingProvider uses a Timer to hit GET /v1/tasks/{taskId}. On status 'complete', call ref.invalidate(wardrobeProvider). Show a CircularProgressIndicator in the gallery view while the provider state is AsyncLoading.

Acceptance Criteria: The wardrobe grid automatically updates with the new item once the background processing task finishes.

Phase 2 — State & Data Flow
[ ] Task: Audit and Synchronize Wardrobe State

Target File(s): lib/features/wardrobe/state/wardrobe_notifier.dart, lib/features/wardrobe/data/wardrobe_repository.dart

Action: Verify wardrobeProvider fetches from the API after invalidation. Ensure the wardrobeRepository updates the local Hive cache with the new list of items returned by the server.

Acceptance Criteria: After an upload, the app shows the new item, and restarting the app maintains the updated list via Hive.

[ ] Task: Repurpose FilteredWardrobeProvider

Target File(s): lib/features/wardrobe/state/wardrobe_notifier.dart

Action: Update filteredWardrobeProvider to act as a Selector that wraps wardrobeProvider. Implement client-side logic to filter by category. Add a comment at the top explaining this is now the authoritative filtered source.

Acceptance Criteria: Changing a filter in the UI updates the gallery items without a new network request.

[ ] Task: Implement Offline Feedback Queuing

Target File(s): lib/features/wardrobe/data/wardrobe_repository.dart

Action: Create a Hive box named feedback_queue. Modify feedback submission to catch Dio connection errors and save the payload to this box. Create a syncPendingFeedback() method to retry these items when the API is reachable.

Acceptance Criteria: Submitting feedback in airplane mode saves the action locally, and it is sent to the server once connection is restored.

[ ] Task: Verify Dio 6.0 Interceptor Security

Target File(s): lib/core/network/dio_provider.dart

Action: Audit Interceptor logic. Ensure Supabase JWT is added to headers. Implement logic to intercept 401 Unauthorized and trigger a Supabase session refresh before retrying the request.

Acceptance Criteria: API calls continue to work seamlessly after the initial JWT expires as long as a valid refresh token exists.

Phase 3 — Application Views & UI Functionality
[ ] Task: Build Garment Detail Screen

Target File(s): lib/features/wardrobe/presentation/garment_detail_screen.dart, lib/features/wardrobe/presentation/garment_card.dart

Action: Create GarmentDetailScreen to display a Hero image, category, and metadata. Replace the SnackBar stub in GarmentCard.onTap with a context.push navigation call to the new screen.

Acceptance Criteria: Tapping a garment card navigates to a full-page view showing the specific item's details.

[ ] Task: Create Upload Progress Banner

Target File(s): lib/features/wardrobe/presentation/widgets/upload_progress_banner.dart, lib/features/wardrobe/presentation/wardrobe_gallery_screen.dart

Action: Build a widget that watches taskPollingProvider. Display progress bar for 'processing', checkmark for 'complete', and error icon for 'failed'. Place at the top of WardrobeGalleryScreen.

Acceptance Criteria: The user sees real-time status feedback during the entire upload and background-removal lifecycle.

[ ] Task: Reconnect AI Recommendation Engine

Target File(s): main.py

Action: Remove random.choice() in GET /v1/recommendations/today. Implement logic to call the engine in app/models/recommendation_schemas.py using pgvector, weather data, and GPT-4o-mini.

Acceptance Criteria: The endpoint returns personalized outfit suggestions based on actual wardrobe items and current weather.

[ ] Task: Render AI Stylist Notes

Target File(s): lib/features/recommendations/presentation/recommendation_card.dart

Action: Locate the stylist_notes field in the parsed model. Add a Text widget in RecommendationCard below the outfit image preview to display these notes.

Acceptance Criteria: The text generated by the AI explaining the outfit choice is visible in the recommendation UI.

Phase 4 — End-to-End Verification
[ ] Task: Create Backend Integration Smoke Test

Target File(s): tests/test_smoke.py

Action: Write an asynchronous test using httpx.AsyncClient. Test must: upload image -> poll until complete -> fetch wardrobe -> verify item -> post feedback.

Acceptance Criteria: Running pytest tests/test_smoke.py passes all steps in a single execution.

[ ] Task: Implement Flutter Upload Flow Widget Test

Target File(s): test/features/wardrobe/upload_flow_test.dart

Action: Use flutter_test and mocktail to mock WardrobeRepository. Simulate FAB tap, mock successful upload, and verify UploadProgressBanner displays 'complete'.

Acceptance Criteria: Test confirms UI responds correctly to the transition of the polling provider state.

[ ] Task: Implement Garment Detail Screen Widget Test

Target File(s): test/features/wardrobe/garment_detail_screen_test.dart

Action: Pump GarmentDetailScreen with sample WardrobeItem. Assert image renders via Hero and metadata fields are present.

Acceptance Criteria: Test passes, confirming the layout correctly handles and displays garment data.

[ ] Task: Perform Full Manual Regression Pass

Target File(s): IMPLEMENTATION_PLAN.md

Action: Walkthrough: 1. Cold start 2. Upload garment (check polling) 3. Verify grid 4. Detail view check 5. Offline skip (check queue) 6. Online sync 7. Verify AI stylist notes.

Acceptance Criteria: All manual steps are completed successfully on a physical device or emulator.
