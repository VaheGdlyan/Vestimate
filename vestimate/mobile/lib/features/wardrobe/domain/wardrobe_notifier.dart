import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';

part 'wardrobe_notifier.g.dart';

class WardrobeItem {
  final String id;
  final String? imageUrl;
  final String status;
  final String? category;
  final Map<String, dynamic>? metadata;

  WardrobeItem({
    required this.id,
    this.imageUrl,
    required this.status,
    this.category,
    this.metadata,
  });

  WardrobeItem copyWith({
    String? status,
    String? imageUrl,
    String? category,
    Map<String, dynamic>? metadata,
  }) {
    return WardrobeItem(
      id: id,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      category: category ?? this.category,
      metadata: metadata ?? this.metadata,
    );
  }

  factory WardrobeItem.fromJson(Map<String, dynamic> json) {
    return WardrobeItem(
      id: json['id'],
      imageUrl: json['segmented_image_url'] ?? json['raw_image_url'],
      status: json['status'],
      category: json['category'],
      metadata: json['metadata'],
    );
  }
}

@riverpod
class Wardrobe extends _$Wardrobe {
  @override
  FutureOr<List<WardrobeItem>> build() async {
    // Re-fetch whenever the filter changes
    final filter = ref.watch(wardrobeCategoryFilterProvider);
    return fetchItems(category: filter == 'All' ? null : filter.toLowerCase());
  }

  Future<List<WardrobeItem>> fetchItems({String? category}) async {
    final repository = ref.read(wardrobeRepositoryProvider);
    final data = await repository.fetchWardrobeItems(category: category);
    return data.map((e) => WardrobeItem.fromJson(e)).toList();
  }

  void addItem(WardrobeItem item) async {
    final currentItems = state.value ?? [];
    state = AsyncData([...currentItems, item]);
  }

  Future<void> deleteItem(String id) async {
    final repo = ref.read(wardrobeRepositoryProvider);
    await repo.deleteWardrobeItem(id);
    ref.invalidateSelf();
  }

  void updateItem(String id, {String? status, String? imageUrl, String? category, Map<String, dynamic>? metadata}) {
    if (state.value == null) return;
    
    state = AsyncData([
      for (final item in state.value!)
        if (item.id == id)
          item.copyWith(status: status, imageUrl: imageUrl, category: category, metadata: metadata)
        else
          item,
    ]);
  }
}

@riverpod
class WardrobeCategoryFilter extends _$WardrobeCategoryFilter {
  @override
  String build() => 'All';

  void setFilter(String category) => state = category;
}

@riverpod
List<WardrobeItem> filteredWardrobe(FilteredWardrobeRef ref) {
  return ref.watch(wardrobeProvider).maybeWhen(
        data: (items) => items,
        orElse: () => [],
      );
}
