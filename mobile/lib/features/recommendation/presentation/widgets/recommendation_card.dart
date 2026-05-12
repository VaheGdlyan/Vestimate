import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';
import 'package:vestimate/features/wardrobe/presentation/widgets/garment_card.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';

class RecommendationCard extends ConsumerWidget {
  final RecommendationState recommendation;

  const RecommendationCard({
    super.key,
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.all(VestimateSpacing.md),
      padding: const EdgeInsets.all(VestimateSpacing.lg),
      decoration: BoxDecoration(
        color: VestimateColors.card,
        borderRadius: BorderRadius.circular(VestimateRadius.card),
        border: Border.all(color: VestimateColors.accent.withOpacity(0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: VestimateColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'TODAY\'S OUTFIT',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: VestimateColors.accent,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: VestimateColors.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(VestimateRadius.chip),
                  border: Border.all(color: VestimateColors.accent.withOpacity(0.2)),
                ),
                child: const Text(
                  '✨ AI STYLIST',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: VestimateColors.accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: VestimateSpacing.md),

          // ── Outfit Items ──────────────────────────────────────────────
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recommendation.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 130,
                  child: GarmentCard(item: recommendation.items[index]),
                );
              },
            ),
          ),

          const SizedBox(height: VestimateSpacing.md),

          // ── Stylist Notes ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(VestimateSpacing.sm),
            decoration: BoxDecoration(
              color: VestimateColors.surface,
              borderRadius: BorderRadius.circular(VestimateRadius.chip),
            ),
            child: Text(
              recommendation.stylistNotes,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VestimateColors.secondary,
                    height: 1.5,
                    fontSize: 12,
                  ),
            ),
          ),

          const SizedBox(height: VestimateSpacing.md),

          // ── Action Buttons ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final repository = ref.read(wardrobeRepositoryProvider);
                    for (final item in recommendation.items) {
                      await repository.sendFeedback(item.id, 'skipped');
                    }
                    if (context.mounted) {
                      ref.invalidate(todayRecommendationProvider);
                    }
                  },
                  child: const Text('SKIP'),
                ),
              ),
              const SizedBox(width: VestimateSpacing.sm),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final repository = ref.read(wardrobeRepositoryProvider);
                    for (final item in recommendation.items) {
                      await repository.sendFeedback(item.id, 'worn');
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('OUTFIT SAVED TO HISTORY ✓'),
                          backgroundColor: VestimateColors.success,
                        ),
                      );
                      ref.invalidate(todayRecommendationProvider);
                    }
                  },
                  child: const Text('WEAR THIS'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
