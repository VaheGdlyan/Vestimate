# VESTIMATE — DEMO SURVIVAL TRIAGE MAP
# Generated: 2026-05-18 | Agent: Senior Full-Stack Triage

## HAPPY PATH
Launch → Home Screen → See Weather + Today's Recommendation → Tap SCAN → Camera Opens → Upload item → Item appears in Closet → Recommendation refreshes → Confirm Look → Tap Stylist tab → Send a chat message → Receive AI-style response

---

## AUDIT: NODE STATUS

### 1. Backend (vestimate/main.py)
| Node | Status | Notes |
|---|---|---|
| Server boot on port 8888 | [OK] | Running, confirmed |
| GET /v1/health | [OK] | Returns correctly |
| GET /v1/weather?lat&lon | [OK] | OpenWeatherMap + fallback working |
| GET /v1/wardrobe/items | [OK] | Reads from test_images2/ folder |
| POST /v1/wardrobe/upload | [SUSPECT] | OpenAI Vision call is async in an endpoint — if OpenAI is slow or key fails, the upload blocks for 10s+ with no user feedback |
| GET /v1/recommendations/today | [OK] | Logic works; fallback note: random category if filename not recognized |
| POST /v1/outfits | [OK] | In-memory, saves correctly |
| GET /v1/outfits/history | [OK] | Enriches with item details |
| GET /v1/outfits | [OK] | Flat list for Riverpod provider |

### 2. Flutter Frontend
| Node | Status | Notes |
|---|---|---|
| Dev auth bypass (kDevAuthBypass=true) | [OK] | SKIP LOGIN button visible |
| Router → MainShell | [OK] | go_router wired |
| HomeTab: Weather chip | [OK] | Falls back gracefully to -- on error |
| HomeTab: Recommendation card | [SUSPECT] | If wardrobeProvider is still loading when recommendation runs, allItems is [] → no items render even though IDs are returned |
| HomeTab: SCAN button → Bottom sheet | [OK] | |
| HomeTab: Camera → CameraScreen | [OK] | But needs full restart to use camera package |
| HomeTab: Gallery → ImagePicker | [OK] | |
| HomeTab: Upload → POST /wardrobe/upload | [SUSPECT] | Blocks 10s+ waiting for OpenAI Vision (no loading indicator during this wait) |
| HomeTab: Confirm Look → POST /v1/outfits | [OK] | |
| ClosetTab: Wardrobe grid | [OK] | Fetches and renders items |
| ClosetTab: Category filter | [BROKEN] | Filter sends "Tops" (capitalized) but backend expects "tops" (lowercase) → filter returns 0 items |
| StylistTab: Chat send | [OK] | Works — uses local hardcoded responses, no real API call needed |
| StylistTab: Chat responses | [SUSPECT] | Hardcoded responses are fine for demo but chatbot note: no real AI call currently |
| OutfitsTab: Today's outfit | [OK] | Same recommendation provider |
| OutfitsTab: History grid | [OK] | Renders SavedOutfit cards |

---

## FIX QUEUE (Prioritized)

### CRITICAL (breaks demo):
1. **[BROKEN] ClosetTab filter**: "Tops" vs "tops" case mismatch
2. **[SUSPECT] Recommendation card shows empty**: race condition - wardrobe not loaded when recommendation resolves

### HIGH (degrades demo):
3. **[SUSPECT] Upload blocks silently**: OpenAI call inside upload is slow — add immediate "Analyzing..." loading feedback to the Scan button flow
4. **[HIGH] Chatbot**: Connect to real OpenAI API endpoint on backend for live AI responses

### POLISH (nice to have if time allows):
5. **[POLISH] Recommendation stylist notes**: Notes are weather-hardcoded to "22°C sunny", make them dynamic
6. **[POLISH] Upload success UX**: After upload, auto-switch to Closet tab so user sees their new item

---

## FILES IN SCOPE (do not touch anything else)
- vestimate/main.py
- vestimate/mobile/lib/features/wardrobe/presentation/screens/home_tab.dart
- vestimate/mobile/lib/features/wardrobe/presentation/screens/closet_tab.dart
- vestimate/mobile/lib/features/wardrobe/presentation/screens/stylist_tab.dart
- vestimate/mobile/lib/features/recommendation/domain/recommendation_provider.dart
- vestimate/mobile/lib/features/wardrobe/domain/wardrobe_notifier.dart

## FILES OUT OF SCOPE
- profile_tab.dart, search_tab.dart (not on happy path)
- garment_detail_screen.dart, wardrobe_gallery_screen.dart (not on happy path)
- All auth files (bypass is working)
- All .g.dart generated files
