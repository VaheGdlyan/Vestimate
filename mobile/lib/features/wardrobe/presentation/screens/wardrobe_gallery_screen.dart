import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';
import 'package:vestimate/features/recommendation/presentation/widgets/recommendation_card.dart';
import 'package:vestimate/features/wardrobe/presentation/widgets/garment_card.dart';

class WardrobeGalleryScreen extends ConsumerWidget {
  const WardrobeGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobeState = ref.watch(wardrobeProvider);
    final currentFilter = ref.watch(wardrobeCategoryFilterProvider);
    final recommendation = ref.watch(todayRecommendationProvider);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: VestimateColors.background,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'WARDROBE',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 20,
                  letterSpacing: 4,
                ),
              ),
              centerTitle: true,
            ),
          ),
          if (currentFilter == 'All')
            recommendation.maybeWhen(
              data: (rec) => rec != null
                  ? SliverToBoxAdapter(child: RecommendationCard(recommendation: rec))
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
              orElse: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            backgroundColor: VestimateColors.surface,
                            selectedColor: VestimateColors.accent.withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: currentFilter == category
                                  ? VestimateColors.accent
                                  : VestimateColors.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          wardrobeState.when(
            data: (items) => SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: items.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'NO ITEMS FOUND',
                          style: TextStyle(
                            color: VestimateColors.secondary.withOpacity(0.5),
                            letterSpacing: 2,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    )
                  : SliverMasonryGrid.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childCount: items.length,
                      itemBuilder: (context, index) {
                        return GarmentCard(item: items[index]);
                      },
                    ),
            ),
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: VestimateColors.accent),
              ),
            ),
            error: (err, stack) => SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'CONNECTION ERROR: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
