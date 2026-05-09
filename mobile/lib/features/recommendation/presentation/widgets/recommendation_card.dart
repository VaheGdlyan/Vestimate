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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VestimateColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: VestimateColors.accent.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: VestimateColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'TODAY\'S OUTFIT',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                  color: VestimateColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recommendation.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 135,
                  child: GarmentCard(item: recommendation.items[index]),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Stylist Notes',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            recommendation.stylistNotes,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: VestimateColors.secondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('RECOМMENDATION SKIPPED')),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VestimateColors.secondary,
                    side: const BorderSide(color: Colors.white10),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('SKIPPED'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                          content: Text('OUTFIT SAVED TO HISTORY!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VestimateColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  child: const Text('WORN TODAY'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
