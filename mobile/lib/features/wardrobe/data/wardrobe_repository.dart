import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/core/network/dio_provider.dart';

part 'wardrobe_repository.g.dart';

class WardrobeRepository {
  final Dio _dio;

  WardrobeRepository(this._dio);

  /// Upload a garment image.
  /// Supports both Mobile (File) and Web (XFile/Bytes).
  Future<Map<String, dynamic>> uploadGarment(dynamic imageFile) async {
    MultipartFile multipartFile;
    String fileName;

    if (imageFile is File) {
      fileName = imageFile.path.split(Platform.pathSeparator).last;
      multipartFile = await MultipartFile.fromFile(
        imageFile.path,
        filename: fileName,
      );
    } else {
      // Assuming XFile for Web/Cross-platform
      final bytes = await imageFile.readAsBytes();
      fileName = imageFile.name;
      multipartFile = MultipartFile.fromBytes(
        bytes,
        filename: fileName,
      );
    }

    final formData = FormData.fromMap({
      'file': multipartFile,
    });

    final response = await _dio.post(
      '/wardrobe/upload',
      data: formData,
    );

    return response.data;
  }

  /// Poll task status for background processing.
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    final response = await _dio.get('/tasks/$taskId');
    return response.data;
  }

  /// Fetch wardrobe items with optional category filter.
  /// Caches the "All" view to Hive for offline support.
  Future<List<Map<String, dynamic>>> fetchWardrobeItems({String? category}) async {
    try {
      final response = await _dio.get(
        '/wardrobe/items',
        queryParameters: category != null ? {'category': category} : null,
      );
      final data = List<Map<String, dynamic>>.from(response.data['items']);

      // Cache the full list for offline fallback
      if (category == null) {
        final box = Hive.box('wardrobe_cache');
        await box.put('items', data);
      }

      return data;
    } catch (e) {
      // If offline, return cached data
      final box = Hive.box('wardrobe_cache');
      final cached = box.get('items');
      if (cached != null) {
        return List<Map<String, dynamic>>.from(cached);
      }
      rethrow;
    }
  }

  /// Fetch today's AI recommendation.
  Future<Map<String, dynamic>> getTodayRecommendation() async {
    final response = await _dio.get('/recommendations/today');
    return response.data;
  }

  /// Submit feedback (worn/skipped). Queues offline if unreachable.
  Future<void> sendFeedback(String itemId, String action) async {
    try {
      await _dio.post('/feedback', data: {
        'item_id': itemId,
        'action': action,
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        // Queue for later sync
        final box = Hive.box('feedback_queue');
        final queue = List<Map<String, dynamic>>.from(box.get('pending', defaultValue: []));
        queue.add({'item_id': itemId, 'action': action});
        await box.put('pending', queue);
        return; // Don't throw — user shouldn't see an error for feedback
      }
      rethrow;
    }
  }

  /// Drain any queued offline feedback.
  Future<int> syncPendingFeedback() async {
    final box = Hive.box('feedback_queue');
    final queue = List<Map<String, dynamic>>.from(box.get('pending', defaultValue: []));
    if (queue.isEmpty) return 0;

    int synced = 0;
    final remaining = <Map<String, dynamic>>[];

    for (final entry in queue) {
      try {
        await _dio.post('/feedback', data: entry);
        synced++;
      } catch (_) {
        remaining.add(entry);
      }
    }

    await box.put('pending', remaining);
    return synced;
  }
}

@riverpod
WardrobeRepository wardrobeRepository(WardrobeRepositoryRef ref) {
  return WardrobeRepository(ref.watch(dioProvider));
}
