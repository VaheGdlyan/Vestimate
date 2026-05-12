import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';

class GarmentDetailScreen extends StatelessWidget {
  final WardrobeItem item;

  const GarmentDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero Image AppBar ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.height * 0.55,
            pinned: true,
            backgroundColor: V.bg,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 30,
                  blur: 15,
                  child: const Icon(Icons.arrow_back, color: V.textPrimary, size: 20),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'garment_${item.id}',
                child: item.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => Container(
                          color: V.bgSurface,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: V.accent,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: V.bgSurface,
                          child: const Icon(Icons.broken_image, size: 48, color: V.textMuted),
                        ),
                      )
                    : Container(
                        color: V.bgSurface,
                        child: const Icon(Icons.checkroom, size: 64, color: V.textMuted),
                      ),
              ),
            ),
          ),

          // ── Details Body ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: V.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(V.r32)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(V.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Badge
                    VTag(item.category ?? 'UNTAGGED', color: V.accent),
                    const SizedBox(height: V.s16),

                    // Item Name
                    Text(
                      item.metadata?['name'] ?? 'Unnamed Item',
                      style: V.h1,
                    ),

                    const SizedBox(height: V.s8),

                    // Status
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.status == 'active' ? V.success : V.textMuted,
                          ),
                        ),
                        const SizedBox(width: V.s8),
                        Text(
                          item.status.toUpperCase(),
                          style: V.label.copyWith(
                            color: item.status == 'active' ? V.success : V.textMuted,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: V.s32),
                    const Divider(),
                    const SizedBox(height: V.s24),

                    // Metadata Section
                    Text(
                      'DETAILS',
                      style: V.label,
                    ),
                    const SizedBox(height: V.s16),

                    _buildDetailRow('Category', item.category?.toUpperCase() ?? '—'),
                    _buildDetailRow('Status', item.status.toUpperCase()),
                    _buildDetailRow('Item ID', item.id),

                    if (item.metadata != null)
                      ...item.metadata!.entries
                          .where((e) => e.key != 'name')
                          .map((e) => _buildDetailRow(e.key.toUpperCase(), e.value.toString())),

                    const SizedBox(height: V.s32),
                    const Divider(),
                    const SizedBox(height: V.s32),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: Consumer(
                            builder: (context, ref, _) {
                              return ElevatedButton.icon(
                                onPressed: () async {
                                  HapticFeedback.mediumImpact();
                                  final repo = ref.read(wardrobeRepositoryProvider);
                                  await repo.sendFeedback(item.id, 'worn');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Marked as worn today ✓'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.checkroom, size: 18),
                                label: const Text('Wear Now'),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: V.s12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _showDeleteConfirmation(context);
                            },
                            icon: const Icon(Icons.delete_outline, size: 18, color: V.danger),
                            label: const Text('Remove', style: TextStyle(color: V.danger)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: V.danger),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: V.s48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V.s12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: V.bodySmall,
          ),
          Text(
            value,
            style: V.body,
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: V.bgSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(V.r24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(V.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: V.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: V.s32),
            const Icon(Icons.warning_amber_rounded, color: V.danger, size: 48),
            const SizedBox(height: V.s16),
            const Text(
              'Remove this item?',
              style: V.h2,
            ),
            const SizedBox(height: V.s8),
            const Text(
              'This action cannot be undone.',
              style: V.bodySmall,
            ),
            const SizedBox(height: V.s32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: V.s12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Item removed from wardrobe'),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: V.danger,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Remove'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: V.s16),
          ],
        ),
      ),
    );
  }
}
