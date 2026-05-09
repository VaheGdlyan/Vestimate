// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wardrobe_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$filteredWardrobeHash() => r'6fe2ea5ed1bafb412fdb7b6b8f79c8f015fd3b0b';

/// See also [filteredWardrobe].
@ProviderFor(filteredWardrobe)
final filteredWardrobeProvider =
    AutoDisposeProvider<List<WardrobeItem>>.internal(
  filteredWardrobe,
  name: r'filteredWardrobeProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$filteredWardrobeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FilteredWardrobeRef = AutoDisposeProviderRef<List<WardrobeItem>>;
String _$wardrobeHash() => r'f5431c3b83478dacbf8942c3595dfa4b3e639ce2';

/// See also [Wardrobe].
@ProviderFor(Wardrobe)
final wardrobeProvider =
    AutoDisposeAsyncNotifierProvider<Wardrobe, List<WardrobeItem>>.internal(
  Wardrobe.new,
  name: r'wardrobeProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$wardrobeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Wardrobe = AutoDisposeAsyncNotifier<List<WardrobeItem>>;
String _$wardrobeCategoryFilterHash() =>
    r'21e84b4d8ffdbe0b1d2097ddd527159afb253be0';

/// See also [WardrobeCategoryFilter].
@ProviderFor(WardrobeCategoryFilter)
final wardrobeCategoryFilterProvider =
    AutoDisposeNotifierProvider<WardrobeCategoryFilter, String>.internal(
  WardrobeCategoryFilter.new,
  name: r'wardrobeCategoryFilterProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$wardrobeCategoryFilterHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WardrobeCategoryFilter = AutoDisposeNotifier<String>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
