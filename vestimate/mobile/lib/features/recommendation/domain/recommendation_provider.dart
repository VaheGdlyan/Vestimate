import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';

part 'recommendation_provider.g.dart';

class RecommendationState {
  final List<WardrobeItem> items;
  final String stylistNotes;

  RecommendationState({
    required this.items,
    required this.stylistNotes,
  });
}

@riverpod
FutureOr<RecommendationState?> todayRecommendation(
    TodayRecommendationRef ref) async {
  // Epic 7 — let errors propagate so home_tab.dart can show the error card.
  // Do NOT catch generically here.
  final repository = ref.read(wardrobeRepositoryProvider);
  final data = await repository.getTodayRecommendation();

  final itemIds = List<String>.from(data['item_ids'] ?? []);
  final stylistNotes = (data['stylist_notes'] as String?) ?? '';

  if (itemIds.isEmpty) {
    return RecommendationState(items: [], stylistNotes: stylistNotes);
  }

  // Watch wardrobe so recommendation refreshes when new items are added
  final allItems = ref.watch(wardrobeProvider).value ?? [];
  final recommendedItems =
      allItems.where((item) => itemIds.contains(item.id)).toList();

  return RecommendationState(
    items: recommendedItems,
    stylistNotes: stylistNotes,
  );
}
