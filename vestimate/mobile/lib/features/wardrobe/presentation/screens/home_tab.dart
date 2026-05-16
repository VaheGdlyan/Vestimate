import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/core/router/nav_provider.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/wardrobe/domain/weather_provider.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';
import 'package:vestimate/features/recommendation/domain/outfit_history_provider.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';
import 'package:image_picker/image_picker.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  late String _timeString;
  late String _dateString;

  @override
  void initState() {
    super.initState();
    _updateTime();
    Stream.periodic(const Duration(minutes: 1)).listen((_) {
      if (mounted) _updateTime();
    });
  }

  void _updateTime() {
    setState(() {
      _timeString = DateFormat('HH:mm').format(DateTime.now());
      _dateString = DateFormat('EEEE, d MMM').format(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final recommendationState = ref.watch(todayRecommendationProvider);
    final weatherState = ref.watch(weatherProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Background (Epic 4 — graceful fallback if asset missing) ───────
          Positioned.fill(
            child: _buildBackground(),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),

          // ── Main Content ────────────────────────────────────────────────
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header: Time + Weather ──────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: V.s24, vertical: V.s20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_timeString,
                                style: V.h1
                                    .copyWith(fontSize: 42, letterSpacing: -1)),
                            Text(_dateString,
                                style: V.bodySmall
                                    .copyWith(color: Colors.white70)),
                          ],
                        ),
                        // Epic 1 — Live weather chip
                        _buildWeatherChip(weatherState),
                      ],
                    ).animate().fade(duration: 500.ms).slideY(begin: -0.1),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s20)),

                // ── Recommendation Card ─────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24),
                    child: recommendationState.when(
                      data: (rec) =>
                          _buildRecommendationCard(context, ref, rec),
                      loading: () => _buildLoadingCard(),
                      // Epic 7 — real error state with retry
                      error: (e, st) => _buildErrorCard(ref, e),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s32)),

                // ── Action Buttons ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _luxuryButton(
                            icon: Icons.camera_alt_outlined,
                            label: 'SCAN',
                            // Epic 2 — shows bottom sheet with Camera/Gallery
                            onTap: () => _showUploadOptions(context, ref),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _luxuryButton(
                            icon: Icons.style_outlined,
                            label: 'OUTFITS',
                            onTap: () => ref
                                .read(bottomNavProvider.notifier)
                                .state = 3,
                          ),
                        ),
                      ],
                    ).animate().fade(duration: 500.ms, delay: 400.ms).slideY(begin: 0.1),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s48)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Epic 4 — Background with fallback gradient ──────────────────────────────
  Widget _buildBackground() {
    return Image.asset(
      'assets/images/luxury_bg.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0D0D), Color(0xFF1A1200), Color(0xFF0A0A0A)],
          ),
        ),
      ),
    ).animate().fade(duration: 800.ms);
  }

  // ── Epic 1 — Weather chip with loading / available / unavailable states ─────
  Widget _buildWeatherChip(AsyncValue<WeatherData> weatherState) {
    return weatherState.when(
      loading: () => _glassContainer(
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  color: V.accent, strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text('...',
                style: V.h3.copyWith(fontSize: 16, color: Colors.white54)),
          ],
        ),
      ),
      data: (weather) => _glassContainer(
        child: Row(
          children: [
            Text(weather.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              weather.tempDisplay,
              style: V.h3.copyWith(fontSize: 18),
            ),
          ],
        ),
      ),
      error: (_, __) => _glassContainer(
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: V.textMuted, size: 18),
            const SizedBox(width: 8),
            Text('--°C',
                style: V.h3.copyWith(fontSize: 18, color: V.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _glassContainer({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(V.r20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(V.r20),
            border:
                Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _luxuryButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: _glassContainer(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(icon, color: V.accent, size: 24),
            const SizedBox(height: 8),
            Text(label,
                style: V.label
                    .copyWith(letterSpacing: 2, fontSize: 10, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ── Recommendation Card ─────────────────────────────────────────────────────
  Widget _buildRecommendationCard(
      BuildContext context, WidgetRef ref, RecommendationState? rec) {
    return Column(
      children: [
        _glassContainer(
          padding: const EdgeInsets.all(V.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: V.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('DAILY SELECTION',
                        style: V.label.copyWith(color: V.accent, fontSize: 10)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Colors.white54, size: 20),
                    onPressed: () =>
                        ref.invalidate(todayRecommendationProvider),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "Today's Masterpiece",
                style: V.h2.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 12),
              Text(
                rec?.stylistNotes ??
                    '"Curating your signature look for today..."',
                style: V.body.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontStyle: FontStyle.italic,
                    height: 1.6),
              ),
              const SizedBox(height: 24),
              if (rec != null && rec.items.isNotEmpty)
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: rec.items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (ctx, i) => _itemPreview(rec.items[i]),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _dummyItemPreview(Icons.checkroom),
                    _dummyItemPreview(Icons.accessibility_new),
                    _dummyItemPreview(Icons.shopping_bag),
                  ],
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: rec != null && rec.items.isNotEmpty
                      ? () => _confirmLook(context, ref, rec)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: V.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(V.r12)),
                  ),
                  child: const Text('CONFIRM LOOK',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fade(duration: 600.ms, delay: 200.ms).slideY(begin: 0.05);
  }

  // Epic 3 — Save outfit to history when confirming look
  Future<void> _confirmLook(
      BuildContext context, WidgetRef ref, RecommendationState rec) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(outfitHistoryProvider.notifier).saveOutfit(
            itemIds: rec.items.map((i) => i.id).toList(),
            stylistNotes: rec.stylistNotes,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Look confirmed & saved to history ✓')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save outfit: $e')),
        );
      }
    }
  }

  Widget _itemPreview(WardrobeItem item) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(V.r12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(V.r12),
        child: item.imageUrl != null
            ? Image.network(item.imageUrl!, fit: BoxFit.cover)
            : const Icon(Icons.checkroom, color: Colors.white38, size: 24),
      ),
    );
  }

  Widget _dummyItemPreview(IconData icon) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Icon(icon, color: Colors.white38, size: 20),
    );
  }

  Widget _buildLoadingCard() {
    return _glassContainer(
      padding: const EdgeInsets.all(V.s48),
      child: const Center(
        child: CircularProgressIndicator(color: V.accent),
      ),
    );
  }

  // Epic 7 — Error card with human-readable message and retry
  Widget _buildErrorCard(WidgetRef ref, Object error) {
    return _glassContainer(
      padding: const EdgeInsets.all(V.s24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: V.danger, size: 32),
          const SizedBox(height: 16),
          const Text("Couldn't fetch today's look", style: V.body),
          const SizedBox(height: 6),
          Text(
            'Check that the local server is running on port 8888.',
            style: V.caption.copyWith(color: V.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.invalidate(todayRecommendationProvider),
            child: const Text('RETRY', style: TextStyle(color: V.accent)),
          ),
        ],
      ),
    );
  }

  // ── Epic 2 — Upload: Camera + Gallery bottom sheet ──────────────────────────
  Future<void> _showUploadOptions(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UploadSourceSheet(),
    );
    if (source == null) return;
    await _handleUpload(context, ref, source);
  }

  Future<void> _handleUpload(
      BuildContext context, WidgetRef ref, ImageSource source) async {
    final picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(source: source, imageQuality: 85);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access ${source == ImageSource.camera ? "camera" : "gallery"}: $e')),
        );
      }
      return;
    }
    if (image == null) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading garment...')),
      );
    }

    try {
      final repo = ref.read(wardrobeRepositoryProvider);
      await repo.uploadGarment(image);
      // Refresh wardrobe after successful upload
      ref.invalidate(wardrobeProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Upload successful! Item added to closet ✓')),
        );
      }
    } on ArgumentError catch (e) {
      // Client-side validation errors
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message.toString()),
              backgroundColor: V.danger),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed. Please try again.'),
              backgroundColor: V.danger),
        );
      }
    }
  }
}

// ── Upload Source Bottom Sheet ─────────────────────────────────────────────────
class _UploadSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(V.s16),
      padding: const EdgeInsets.all(V.s24),
      decoration: BoxDecoration(
        color: V.bgCard,
        borderRadius: BorderRadius.circular(V.r24),
        border: Border.all(color: V.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: V.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: V.s24),
          Text('ADD GARMENT', style: V.label.copyWith(letterSpacing: 3)),
          const SizedBox(height: V.s24),
          Row(
            children: [
              Expanded(
                child: _SourceButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ),
              const SizedBox(width: V.s16),
              Expanded(
                child: _SourceButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: V.s16),
          Text(
            'JPEG, PNG or WebP · Max 10 MB',
            style: V.caption.copyWith(color: V.textMuted),
          ),
          const SizedBox(height: V.s8),
        ],
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: V.s24),
        decoration: BoxDecoration(
          color: V.bgSurface,
          borderRadius: BorderRadius.circular(V.r16),
          border: Border.all(color: V.border, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: V.accent, size: 32),
            const SizedBox(height: V.s8),
            Text(label,
                style: V.body.copyWith(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
