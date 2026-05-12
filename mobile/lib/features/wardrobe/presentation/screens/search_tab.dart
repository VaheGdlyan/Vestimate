import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/garment_detail_screen.dart';

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final wardrobeState = ref.watch(wardrobeProvider);

    return SafeArea(
      child: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(VestimateSpacing.md),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search your wardrobe...',
                hintStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: VestimateColors.muted,
                ),
                prefixIcon: const Icon(Icons.search, color: VestimateColors.muted),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: VestimateColors.muted),
                        onPressed: () => setState(() => _query = ''),
                      )
                    : null,
              ),
            ),
          ),

          // Results
          Expanded(
            child: wardrobeState.when(
              data: (items) {
                final filtered = _query.isEmpty
                    ? items
                    : items.where((i) {
                        final name = (i.metadata?['name'] ?? '').toString().toLowerCase();
                        final cat = (i.category ?? '').toLowerCase();
                        return name.contains(_query) || cat.contains(_query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: VestimateColors.muted.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty ? 'TYPE TO SEARCH' : 'NO RESULTS',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 2, color: VestimateColors.muted),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: VestimateSpacing.md),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: VestimateColors.card,
                          borderRadius: BorderRadius.circular(VestimateRadius.grid),
                          border: Border.all(color: VestimateColors.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(VestimateRadius.grid),
                          child: item.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.imageUrl!,
                                  fit: BoxFit.contain,
                                )
                              : const Icon(Icons.checkroom, color: VestimateColors.muted, size: 20),
                        ),
                      ),
                      title: Text(
                        item.metadata?['name'] ?? 'Unnamed',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        item.category?.toUpperCase() ?? '',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: VestimateColors.accent),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: VestimateColors.muted, size: 18),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => GarmentDetailScreen(item: item)),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: VestimateColors.accent),
              ),
              error: (e, st) => Center(
                child: Text('Error loading wardrobe', style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
