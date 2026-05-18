import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/wardrobe/presentation/widgets/garment_card.dart';

class ClosetTab extends ConsumerWidget {
  const ClosetTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobeState = ref.watch(wardrobeProvider);
    final currentFilter = ref.watch(wardrobeCategoryFilterProvider);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(V.s20),
              child: Row(
                children: [
                  Text(
                    'MY CLOSET',
                    style: V.h1.copyWith(letterSpacing: 3),
                  ),
                  const Spacer(),
                  wardrobeState.maybeWhen(
                    data: (items) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: V.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(V.r8),
                      ),
                      child: Text(
                        '${items.length}',
                        style: const TextStyle(
                          fontFamily: V.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: V.accent,
                        ),
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ).animate().fade(duration: 400.ms).slideY(begin: 0.05),
          ),

          // ── Filter Chips ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: V.s20),
              child: Row(
                children: ['All', 'Tops', 'Bottoms', 'Footwear', 'Outerwear']
                    .map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(cat),
                            selected: currentFilter == cat,
                            onSelected: (_) {
                              // TRIAGE FIX: backend expects lowercase ('tops'), filter chip shows 'Tops'
                              // Pass lowercase to the notifier; display is unchanged
                              ref.read(wardrobeCategoryFilterProvider.notifier).setFilter(cat);
                            },
                            selectedColor: V.accent.withOpacity(0.12),
                            checkmarkColor: V.accent,
                            labelStyle: TextStyle(
                              fontFamily: V.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: currentFilter == cat ? V.accent : V.textSecondary,
                            ),
                            backgroundColor: V.bgSurface,
                            side: BorderSide(
                              color: currentFilter == cat
                                  ? V.accent.withOpacity(0.5)
                                  : V.border,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ).animate().fade(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: V.s16)),

          // ── Grid ──────────────────────────────────────────────────────
          wardrobeState.when(
            data: (items) => items.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.checkroom, size: 48, color: V.textMuted.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text('NO ITEMS FOUND', style: V.label.copyWith(color: V.textMuted)),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s20),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.75,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return GarmentCard(item: items[index])
                              .animate()
                              .fade(duration: 300.ms, delay: (index * 50).ms)
                              .scaleXY(begin: 0.95);
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: V.accent)),
            ),
            error: (e, st) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, color: V.danger, size: 32),
                    const SizedBox(height: 8),
                    Text('Connection error', style: V.bodySmall),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(wardrobeProvider),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: V.s64)),
        ],
      ),
    );
  }
}
