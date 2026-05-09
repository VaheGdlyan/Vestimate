import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/features/wardrobe/data/wardrobe_repository.dart';

part 'task_polling_provider.g.dart';

enum TaskStatus {
  pending,
  processing,
  complete,
  failed;

  static TaskStatus fromString(String status) {
    switch (status) {
      case 'pending':
        return TaskStatus.pending;
      case 'processing':
        return TaskStatus.processing;
      case 'complete':
        return TaskStatus.complete;
      case 'failed':
        return TaskStatus.failed;
      default:
        return TaskStatus.pending;
    }
  }
}

class TaskState {
  final String taskId;
  final TaskStatus status;
  final String? itemId;
  final String? error;

  TaskState({
    required this.taskId,
    required this.status,
    this.itemId,
    this.error,
  });
}

@riverpod
class TaskPolling extends _$TaskPolling {
  Timer? _timer;

  @override
  FutureOr<TaskState?> build(String taskId) {
    ref.onDispose(() => _timer?.cancel());
    _startPolling(taskId);
    return null;
  }

  void _startPolling(String taskId) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final repository = ref.read(wardrobeRepositoryProvider);
        final data = await repository.getTaskStatus(taskId);
        
        final status = TaskStatus.fromString(data['status']);
        final newState = TaskState(
          taskId: taskId,
          status: status,
          itemId: data['item_id'],
          error: data['error'],
        );

        state = AsyncData(newState);

        if (status == TaskStatus.complete || status == TaskStatus.failed) {
          timer.cancel();
        }
      } catch (e, st) {
        state = AsyncError(e, st);
        timer.cancel();
      }
    });
  }
}
