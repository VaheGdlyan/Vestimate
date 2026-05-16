import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';

part 'outfit_history_provider.g.dart';

// ── Data Models ───────────────────────────────────────────────────────────────

class SavedOutfit {
  final String id;
  final List<WardrobeItem> items;
  final String stylistNotes;
  final DateTime savedAt;

  const SavedOutfit({
    required this.id,
    required this.items,
    required this.stylistNotes,
    required this.savedAt,
  });

  factory SavedOutfit.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? []);
    return SavedOutfit(
      id: json['id'] as String,
      items: rawItems
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      stylistNotes: json['stylist_notes'] as String? ?? '',
      savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// First item's image URL for use as a cover thumbnail.
  String? get coverImageUrl =>
      items.isNotEmpty ? items.first.imageUrl : null;

  /// E.g. "May 16" formatted date label.
  String get dateLabel {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[savedAt.month]} ${savedAt.day}';
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

@riverpod
class OutfitHistory extends _$OutfitHistory {
  @override
  Future<List<SavedOutfit>> build() async {
    return _fetchHistory();
  }

  Future<List<SavedOutfit>> _fetchHistory() async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      '/outfits/history',
      queryParameters: {'limit': 50, 'offset': 0},
    );
    final outfits = (response.data['outfits'] as List<dynamic>? ?? []);
    return outfits
        .map((e) => SavedOutfit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Saves the current recommendation as an outfit, then refreshes the list.
  Future<void> saveOutfit({
    required List<String> itemIds,
    required String stylistNotes,
  }) async {
    final dio = ref.read(dioProvider);
    await dio.post('/outfits', data: {
      'item_ids': itemIds,
      'stylist_notes': stylistNotes,
    });
    // Optimistically refresh
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchHistory);
  }
}
