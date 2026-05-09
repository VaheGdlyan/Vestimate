import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';

class GarmentCard extends StatelessWidget {
  final WardrobeItem item;

  const GarmentCard({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VestimateColors.surface,
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            VestimateColors.surface,
            VestimateColors.surface.withOpacity(0.5),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 0.75, // Standard luxury portrait ratio
          child: Stack(
            children: [
              if (item.imageUrl != null)
                Center(
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Container(
                      color: Colors.white10,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                ),
              if (item.status == 'processing')
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: Text(
                      'DIGITIZING...',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Text(
                  item.category?.toUpperCase() ?? 'UNTAGGED',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VestimateColors.accent.withOpacity(0.8),
                    fontSize: 8,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
