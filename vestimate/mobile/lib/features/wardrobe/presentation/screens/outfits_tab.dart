import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';
import 'package:vestimate/features/recommendation/domain/outfit_history_provider.dart';

class OutfitsTab extends ConsumerWidget {
  const OutfitsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendationState = ref.watch(todayRecommendationProvider);
    final historyState = ref.watch(outfitHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Ambient glow accent
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: V.accent.withOpacity(0.05),
              ),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header ─────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(V.s24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('COLLECTIONS',
                            style: V.label.copyWith(
                                letterSpacing: 4, color: V.accent)),
                        const SizedBox(height: 8),
                        Text('Your AI Outfits', style: V.h1),
                      ],
                    ),
                  ).animate().fade(duration: 500.ms).slideX(begin: -0.05),
                ),

                // ── Featured: Today's Outfit ────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24),
                    child: recommendationState.when(
                      data: (rec) =>
                          _buildFeaturedOutfit(context, ref, rec),
                      loading: () => const Center(
                          child: CircularProgressIndicator(color: V.accent)),
                      // Epic 7 — show actual error message + retry
                      error: (e, st) => _buildErrorState(
                        ref,
                        message: 'Could not load today\'s outfit.',
                        onRetry: () =>
                            ref.invalidate(todayRecommendationProvider),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s32)),

                // ── History Gallery Header ──────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: V.s24),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Text('HISTORY',
                            style: V.label.copyWith(letterSpacing: 2)),
                        const Spacer(),
                        historyState.maybeWhen(
                          data: (outfits) => Text(
                            '${outfits.length} saved',
                            style:
                                V.caption.copyWith(color: V.textSecondary),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // ── History Grid (Epic 3 — real data) ──────────────────────
                historyState.when(
                  data: (outfits) {
                    if (outfits.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(V.s32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.style_outlined,
                                    color: V.textMuted, size: 40),
                                SizedBox(height: 12),
                                Text('No saved outfits yet.',
                                    style: V.bodySmall),
                                SizedBox(height: 6),
                                Text(
                                    'Confirm a look on the Home tab to save it here.',
                                    style: V.caption,
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: V.s24),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildHistoryCard(outfits[index], index),
                          childCount: outfits.length,
                        ),
                      ),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator(color: V.accent)),
                  ),
                  // Epic 7 — error state with retry
                  error: (e, st) => SliverToBoxAdapter(
                    child: _buildErrorState(
                      ref,
                      message: 'Could not load outfit history.',
                      onRetry: () => ref.invalidate(outfitHistoryProvider),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s64)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedOutfit(
      BuildContext context, WidgetRef ref, RecommendationState? rec) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: V.bgCard,
        borderRadius: BorderRadius.circular(V.r24),
        border: Border.all(color: V.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(V.r24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image — first recommended item
            Container(
              height: 200,
              width: double.infinity,
              color: V.bgSurface,
              child: rec != null &&
                      rec.items.isNotEmpty &&
                      rec.items[0].imageUrl != null
                  ? Image.network(rec.items[0].imageUrl!, fit: BoxFit.cover)
                  : Center(
                      child: Icon(Icons.style,
                          color: Colors.white.withOpacity(0.1), size: 64),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("TODAY'S SIGNATURE",
                      style: V.label.copyWith(color: V.accent)),
                  const SizedBox(height: 8),
                  Text('Modern Editorial', style: V.h3),
                  const SizedBox(height: 4),
                  Text('AI curated just for you', style: V.caption),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: rec != null && rec.items.isNotEmpty
                              ? () => _saveAndConfirm(context, ref, rec)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: V.accent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                          ),
                          child: const Text('WEAR THIS'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: V.bgSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: V.border),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.share_outlined,
                              size: 20),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fade(duration: 600.ms, delay: 200.ms).slideY(begin: 0.1);
  }

  Future<void> _saveAndConfirm(
      BuildContext context, WidgetRef ref, RecommendationState rec) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(outfitHistoryProvider.notifier).saveOutfit(
            itemIds: rec.items.map((i) => i.id).toList(),
            stylistNotes: rec.stylistNotes,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outfit saved to history ✓')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  // Epic 3 — History card built from real SavedOutfit data
  Widget _buildHistoryCard(SavedOutfit outfit, int index) {
    return Container(
      decoration: BoxDecoration(
        color: V.bgCard,
        borderRadius: BorderRadius.circular(V.r20),
        border: Border.all(color: V.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(V.r20)),
              child: outfit.coverImageUrl != null
                  ? Image.network(
                      outfit.coverImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: V.bgSurface,
                        child: const Center(
                          child: Icon(Icons.style,
                              color: Colors.white10, size: 32),
                        ),
                      ),
                    )
                  : Container(
                      color: V.bgSurface,
                      child: const Center(
                        child: Icon(Icons.style,
                            color: Colors.white10, size: 32),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${outfit.items.length} ITEMS',
                  style: V.bodySmall.copyWith(
                      color: V.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 9),
                ),
                Text(outfit.dateLabel, style: V.caption),
              ],
            ),
          ),
        ],
      ),
    ).animate().fade(duration: 400.ms, delay: (400 + index * 100).ms).scale(
        begin: const Offset(0.95, 0.95));
  }

  // Epic 7 — Reusable error state widget
  Widget _buildErrorState(
    WidgetRef ref, {
    required String message,
    required VoidCallback onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.all(V.s32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: V.danger, size: 32),
          const SizedBox(height: 12),
          Text(message, style: V.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}
