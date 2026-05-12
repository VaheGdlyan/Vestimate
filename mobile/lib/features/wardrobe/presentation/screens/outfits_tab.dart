import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';

class OutfitsTab extends ConsumerWidget {
  const OutfitsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendationState = ref.watch(todayRecommendationProvider);
    final wardrobeState = ref.watch(wardrobeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(V.s24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('COLLECTIONS', style: V.label.copyWith(letterSpacing: 4, color: V.accent)),
                        const SizedBox(height: 8),
                        Text('Your AI Outfits', style: V.h1),
                      ],
                    ),
                  ).animate().fade(duration: 500.ms).slideX(begin: -0.05),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s24),
                    child: recommendationState.when(
                      data: (rec) => _buildFeaturedOutfit(context, ref, rec),
                      loading: () => const Center(child: CircularProgressIndicator(color: V.accent)),
                      error: (e, st) => const SizedBox.shrink(),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s32)),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: V.s24),
                  sliver: SliverToBoxAdapter(
                    child: Text('GALLERY', style: V.label.copyWith(letterSpacing: 2)),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                wardrobeState.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Center(child: Text('No items in wardrobe yet', style: V.caption)),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: V.s24),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildPastOutfitCard(items[index % items.length], index);
                          },
                          childCount: items.length > 4 ? 4 : items.length,
                        ),
                      ),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
                  error: (e, st) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: V.s64)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedOutfit(BuildContext context, WidgetRef ref, dynamic rec) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: V.bgCard,
        borderRadius: BorderRadius.circular(V.r24),
        border: Border.all(color: V.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(V.r24),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  color: V.bgSurface,
                  child: rec != null && rec.items.isNotEmpty && rec.items[0].imageUrl != null
                      ? Image.network(rec.items[0].imageUrl!, fit: BoxFit.cover)
                      : Center(
                          child: Icon(Icons.style, color: Colors.white.withOpacity(0.1), size: 64),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TODAY\'S SIGNATURE', style: V.label.copyWith(color: V.accent)),
                      const SizedBox(height: 8),
                      Text('Modern Editorial', style: V.h3),
                      const SizedBox(height: 4),
                      Text('AI curated just for you', style: V.caption),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Look marked as worn ✓')),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: V.accent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                              icon: const Icon(Icons.share_outlined, size: 20),
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
          ],
        ),
      ),
    ).animate().fade(duration: 600.ms, delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildPastOutfitCard(WardrobeItem item, int index) {
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(V.r20)),
              child: item.imageUrl != null
                  ? Image.network(item.imageUrl!, fit: BoxFit.cover, width: double.infinity)
                  : Container(
                      color: V.bgSurface,
                      child: const Center(
                        child: Icon(Icons.history, color: Colors.white10, size: 32),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.category?.toUpperCase() ?? 'OUTFIT', style: V.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                Text('Archive #${10 - index}', style: V.caption),
              ],
            ),
          ),
        ],
      ),
    ).animate().fade(duration: 400.ms, delay: (400 + index * 100).ms).scale(begin: const Offset(0.95, 0.95));
  }
}
