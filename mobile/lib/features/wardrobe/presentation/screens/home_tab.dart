import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/core/router/nav_provider.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';
import 'package:image_picker/image_picker.dart';

// Import dart:io safely. It's allowed on web, but classes throw at runtime.
import 'dart:io' as io; 

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
    _timeString = DateFormat('HH:mm').format(DateTime.now());
    _dateString = DateFormat('EEEE, d MMM').format(DateTime.now());
    Stream.periodic(const Duration(minutes: 1)).listen((_) {
      if (mounted) {
        setState(() {
          _timeString = DateFormat('HH:mm').format(DateTime.now());
          _dateString = DateFormat('EEEE, d MMM').format(DateTime.now());
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final recommendationState = ref.watch(todayRecommendationProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Background Image ───────────────────────────────────────────
          Positioned.fill(
            child: Image.asset(
              'assets/images/luxury_bg.png',
              fit: BoxFit.cover,
            ).animate().fade(duration: 800.ms),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),

          // ── Main Content ───────────────────────────────────────────────
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24, vertical: V.s20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_timeString, style: V.h1.copyWith(fontSize: 42, letterSpacing: -1)),
                            Text(_dateString, style: V.bodySmall.copyWith(color: Colors.white70)),
                          ],
                        ),
                        _glassContainer(
                          child: Row(
                            children: [
                              const Icon(Icons.wb_sunny_rounded, color: V.accent, size: 20),
                              const SizedBox(width: 8),
                              Text('22°C', style: V.h3.copyWith(fontSize: 18)),
                            ],
                          ),
                        ),
                      ],
                    ).animate().fade(duration: 500.ms).slideY(begin: -0.1),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s20)),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24),
                    child: recommendationState.when(
                      data: (rec) => _buildRecommendationCard(context, ref, rec),
                      loading: () => _buildLoadingCard(),
                      error: (e, st) => _buildErrorCard(ref),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s32)),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _luxuryButton(
                            icon: Icons.camera_alt_outlined,
                            label: 'SCAN',
                            onTap: () => _handleUpload(context, ref),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _luxuryButton(
                            icon: Icons.style_outlined,
                            label: 'OUTFITS',
                            onTap: () => ref.read(bottomNavProvider.notifier).state = 3,
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

  Widget _glassContainer({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(V.r20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(V.r20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _luxuryButton({required IconData icon, required String label, required VoidCallback onTap}) {
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
            Text(label, style: V.label.copyWith(letterSpacing: 2, fontSize: 10, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(BuildContext context, WidgetRef ref, dynamic rec) {
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: V.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('DAILY SELECTION', style: V.label.copyWith(color: V.accent, fontSize: 10)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
                    onPressed: () => ref.invalidate(todayRecommendationProvider),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Today\'s Masterpiece',
                style: V.h2.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 12),
              Text(
                rec?.stylistNotes ?? '“Curating your signature look for today...”',
                style: V.body.copyWith(color: Colors.white.withOpacity(0.9), fontStyle: FontStyle.italic, height: 1.6),
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
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Look confirmed. Have a great day!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: V.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.r12)),
                  ),
                  child: const Text('CONFIRM LOOK', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fade(duration: 600.ms, delay: 200.ms).slideY(begin: 0.05);
  }

  Widget _itemPreview(WardrobeItem item) {
    return Container(
      width: 100, height: 100,
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
      width: 60, height: 60,
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

  Widget _buildErrorCard(WidgetRef ref) {
    return _glassContainer(
      padding: const EdgeInsets.all(V.s24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: V.danger, size: 32),
          const SizedBox(height: 16),
          const Text('Couldn\'t fetch today\'s look', style: V.body),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.invalidate(todayRecommendationProvider),
            child: const Text('RETRY', style: TextStyle(color: V.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpload(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading your garment...')),
      );
    }

    try {
      final repo = ref.read(wardrobeRepositoryProvider);
      
      // Directly pass the XFile (image) which is now supported by our repository
      await repo.uploadGarment(image);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload successful! Item is being digitized.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }
}
