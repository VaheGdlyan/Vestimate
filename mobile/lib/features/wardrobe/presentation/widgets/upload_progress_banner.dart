import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/task_polling_provider.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';

class UploadProgressBanner extends ConsumerWidget {
  const UploadProgressBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskId = ref.watch(activeTaskIdProvider);
    if (taskId == null) return const SizedBox.shrink();

    final asyncPollingState = ref.watch(taskPollingProvider(taskId));

    return asyncPollingState.when(
      data: (pollingState) {
        if (pollingState == null) return const SizedBox.shrink();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: V.s20, vertical: V.s8),
          padding: const EdgeInsets.symmetric(horizontal: V.s16, vertical: V.s12),
          decoration: BoxDecoration(
            color: _getBannerColor(pollingState.status).withOpacity(0.1),
            borderRadius: BorderRadius.circular(V.r12),
            border: Border.all(
              color: _getBannerColor(pollingState.status).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              _buildIcon(pollingState.status),
              const SizedBox(width: V.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getTitle(pollingState.status),
                      style: V.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _getBannerColor(pollingState.status),
                      ),
                    ),
                    Text(
                      _getSubtitle(pollingState.status),
                      style: V.caption,
                    ),
                  ],
                ),
              ),
              if (pollingState.status == TaskStatus.complete || pollingState.status == TaskStatus.failed)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: V.textMuted,
                  onPressed: () {
                    ref.read(activeTaskIdProvider.notifier).setTaskId(null);
                    if (pollingState.status == TaskStatus.complete) {
                      ref.invalidate(wardrobeProvider);
                    }
                  },
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }

  Color _getBannerColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
      case TaskStatus.processing:
        return V.info;
      case TaskStatus.complete:
        return V.success;
      case TaskStatus.failed:
        return V.danger;
      default:
        return V.textMuted;
    }
  }

  Widget _buildIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
      case TaskStatus.processing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: V.info,
          ),
        );
      case TaskStatus.complete:
        return const Icon(Icons.check_circle, color: V.success, size: 28);
      case TaskStatus.failed:
        return const Icon(Icons.error, color: V.danger, size: 28);
      default:
        return const Icon(Icons.cloud_upload, color: V.textMuted, size: 28);
    }
  }

  String _getTitle(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'Uploading Image...';
      case TaskStatus.processing:
        return 'Removing Background...';
      case TaskStatus.complete:
        return 'Garment Digitized!';
      case TaskStatus.failed:
        return 'Processing Failed';
      default:
        return 'Unknown Status';
    }
  }

  String _getSubtitle(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'Sending to Vestimate AI';
      case TaskStatus.processing:
        return 'AI is extracting the garment';
      case TaskStatus.complete:
        return 'Tap to view in your closet';
      case TaskStatus.failed:
        return 'Please try again with a clearer image';
      default:
        return '';
    }
  }
}
