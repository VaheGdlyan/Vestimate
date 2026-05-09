// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_polling_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$taskPollingHash() => r'3d2569bedd11cb1f9cb685e055e1608a65672f48';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$TaskPolling
    extends BuildlessAutoDisposeAsyncNotifier<TaskState?> {
  late final String taskId;

  FutureOr<TaskState?> build(
    String taskId,
  );
}

/// See also [TaskPolling].
@ProviderFor(TaskPolling)
const taskPollingProvider = TaskPollingFamily();

/// See also [TaskPolling].
class TaskPollingFamily extends Family<AsyncValue<TaskState?>> {
  /// See also [TaskPolling].
  const TaskPollingFamily();

  /// See also [TaskPolling].
  TaskPollingProvider call(
    String taskId,
  ) {
    return TaskPollingProvider(
      taskId,
    );
  }

  @override
  TaskPollingProvider getProviderOverride(
    covariant TaskPollingProvider provider,
  ) {
    return call(
      provider.taskId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'taskPollingProvider';
}

/// See also [TaskPolling].
class TaskPollingProvider
    extends AutoDisposeAsyncNotifierProviderImpl<TaskPolling, TaskState?> {
  /// See also [TaskPolling].
  TaskPollingProvider(
    String taskId,
  ) : this._internal(
          () => TaskPolling()..taskId = taskId,
          from: taskPollingProvider,
          name: r'taskPollingProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$taskPollingHash,
          dependencies: TaskPollingFamily._dependencies,
          allTransitiveDependencies:
              TaskPollingFamily._allTransitiveDependencies,
          taskId: taskId,
        );

  TaskPollingProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.taskId,
  }) : super.internal();

  final String taskId;

  @override
  FutureOr<TaskState?> runNotifierBuild(
    covariant TaskPolling notifier,
  ) {
    return notifier.build(
      taskId,
    );
  }

  @override
  Override overrideWith(TaskPolling Function() create) {
    return ProviderOverride(
      origin: this,
      override: TaskPollingProvider._internal(
        () => create()..taskId = taskId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        taskId: taskId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<TaskPolling, TaskState?>
      createElement() {
    return _TaskPollingProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TaskPollingProvider && other.taskId == taskId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, taskId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin TaskPollingRef on AutoDisposeAsyncNotifierProviderRef<TaskState?> {
  /// The parameter `taskId` of this provider.
  String get taskId;
}

class _TaskPollingProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<TaskPolling, TaskState?>
    with TaskPollingRef {
  _TaskPollingProviderElement(super.provider);

  @override
  String get taskId => (origin as TaskPollingProvider).taskId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
