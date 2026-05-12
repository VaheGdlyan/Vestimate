import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/wardrobe/domain/task_polling_provider.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';
import 'package:vestimate/features/recommendation/presentation/widgets/recommendation_card.dart';
import 'package:vestimate/features/wardrobe/presentation/widgets/garment_card.dart';
import 'package:vestimate/features/wardrobe/presentation/widgets/upload_progress_banner.dart';

class WardrobeGalleryScreen extends ConsumerWidget {
  const WardrobeGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobeState = ref.watch(wardrobeProvider);
    final currentFilter = ref.watch(wardrobeCategoryFilterProvider);
    final recommendation = ref.watch(todayRecommendationProvider);

    return Scaffold(
      backgroundColor: VestimateColors.background,
      body: Column(
        children: [
          // Upload Progress Banner
          const SafeArea(bottom: false, child: UploadProgressBanner()),

          // Main Content
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── App Bar ─────────────────────────────────────────────
                SliverAppBar(
                  expandedHeight: 80,
                  floating: true,
                  pinned: true,
                  backgroundColor: VestimateColors.background,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.checkroom, color: VestimateColors.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'VESTIMATE',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              letterSpacing: 4,
                              color: VestimateColors.accent,
                            ),
                      ),
                    ],
                  ),
                  centerTitle: true,
                ),

                // ── Recommendation Card ─────────────────────────────────
                if (currentFilter == 'All')
                  recommendation.maybeWhen(
                    data: (rec) => rec != null
                        ? SliverToBoxAdapter(child: RecommendationCard(recommendation: rec))
                        : const SliverToBoxAdapter(child: SizedBox.shrink()),
                    orElse: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                  ),

                // ── Category Filter Chips ───────────────────────────────
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: VestimateSpacing.md,
                      vertical: VestimateSpacing.xs,
                    ),
                    child: Row(
                      children: ['All', 'Tops', 'Bottoms', 'Footwear', 'Outerwear']
                          .map((category) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category),
                                  selected: currentFilter == category,
                                  onSelected: (selected) {
                                    ref
                                        .read(wardrobeCategoryFilterProvider.notifier)
                                        .setFilter(category);
                                  },
                                  selectedColor: VestimateColors.accent.withOpacity(0.06),
                                  checkmarkColor: VestimateColors.accent,
                                  labelStyle: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: currentFilter == category
                                        ? VestimateColors.accent
                                        : VestimateColors.secondary,
                                  ),
                                  side: BorderSide(
                                    color: currentFilter == category
                                        ? VestimateColors.accent.withOpacity(0.5)
                                        : VestimateColors.border,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),

                // ── Wardrobe Grid ───────────────────────────────────────
                wardrobeState.when(
                  data: (items) => items.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(context, ref),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.all(VestimateSpacing.md),
                          sliver: SliverMasonryGrid.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childCount: items.length,
                            itemBuilder: (context, index) {
                              return GarmentCard(item: items[index]);
                            },
                          ),
                        ),
                  loading: () => SliverPadding(
                    padding: const EdgeInsets.all(VestimateSpacing.md),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childCount: 6,
                      itemBuilder: (context, index) => _buildSkeletonCard(),
                    ),
                  ),
                  error: (err, stack) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildErrorState(context, ref, err),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // ── FAB: Upload ─────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        heroTag: 'upload_fab',
        onPressed: () => _handleUpload(context, ref),
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  // ── Upload Handler ──────────────────────────────────────────────────────
  Future<void> _handleUpload(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final file = File(image.path);
    try {
      final repo = ref.read(wardrobeRepositoryProvider);
      final result = await repo.uploadGarment(file);
      final taskId = result['task_id'];
      ref.read(activeTaskIdProvider.notifier).setTaskId(taskId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: VestimateColors.danger,
          ),
        );
      }
    }
  }

  // ── Empty State ─────────────────────────────────────────────────────────
  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checkroom, size: 64, color: VestimateColors.muted.withOpacity(0.5)),
          const SizedBox(height: VestimateSpacing.md),
          Text(
            'YOUR WARDROBE IS EMPTY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: VestimateColors.muted,
                ),
          ),
          const SizedBox(height: VestimateSpacing.xs),
          Text(
            'Tap the camera button to add your first item',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: VestimateSpacing.xl),
          ElevatedButton.icon(
            onPressed: () => _handleUpload(context, ref),
            icon: const Icon(Icons.add_a_photo, size: 18),
            label: const Text('ADD ITEM'),
          ),
        ],
      ),
    );
  }

  // ── Error State ─────────────────────────────────────────────────────────
  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VestimateSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: VestimateColors.danger),
            const SizedBox(height: VestimateSpacing.md),
            Text(
              'CONNECTION ERROR',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: VestimateColors.danger,
                  ),
            ),
            const SizedBox(height: VestimateSpacing.xs),
            Text(
              err.toString(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VestimateColors.muted,
                    fontSize: 11,
                  ),
            ),
            const SizedBox(height: VestimateSpacing.xl),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(wardrobeProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Skeleton Card ───────────────────────────────────────────────────────
  Widget _buildSkeletonCard() {
    return Container(
      decoration: BoxDecoration(
        color: VestimateColors.shimmerBase,
        borderRadius: BorderRadius.circular(VestimateRadius.card),
        border: Border.all(color: VestimateColors.border),
      ),
      child: AspectRatio(
        aspectRatio: 0.75,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VestimateRadius.card),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                VestimateColors.shimmerBase,
                VestimateColors.shimmerHighlight,
                VestimateColors.shimmerBase,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
