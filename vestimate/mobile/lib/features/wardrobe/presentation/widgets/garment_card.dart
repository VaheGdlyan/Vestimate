import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/garment_detail_screen.dart';

class GarmentCard extends StatelessWidget {
  final WardrobeItem item;

  const GarmentCard({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      borderRadius: V.r16,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GarmentDetailScreen(item: item),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(V.r16),
        child: AspectRatio(
          aspectRatio: 0.82,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Image ────────────────────────────────────────────────────────
              if (item.imageUrl != null)
                Hero(
                  tag: 'garment_${item.id}',
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => _buildSkeleton(),
                    errorWidget: (context, url, error) => Container(
                      color: V.bgSurface,
                      child: const Icon(Icons.broken_image, color: V.textMuted, size: 24),
                    ),
                  ),
                ),

              // ── Processing Overlay ──────────────────────────────────────────
              if (item.status == 'processing')
                Container(
                  color: V.bg.withOpacity(0.7),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: V.accent,
                          ),
                        ),
                        SizedBox(height: V.s8),
                        Text(
                          'DIGITIZING...',
                          style: V.label,
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Category Label ──────────────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        V.bg.withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    item.category?.toUpperCase() ?? 'UNTAGGED',
                    style: V.label.copyWith(color: V.accentSoft, fontSize: 9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      color: V.shimmerBase,
    );
  }
}
