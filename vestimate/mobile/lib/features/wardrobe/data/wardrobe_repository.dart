import 'package:dio/dio.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/core/network/dio_provider.dart';

part 'wardrobe_repository.g.dart';

class WardrobeRepository {
  final Dio _dio;

  WardrobeRepository(this._dio);

  /// Upload a garment image from an [XFile] (image_picker).
  /// Uses bytes path — safe for both mobile and web (no dart:io).
  Future<Map<String, dynamic>> uploadGarment(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final fileName = imageFile.name.isNotEmpty ? imageFile.name : 'upload.jpg';

    // Client-side MIME validation
    final mimeType = imageFile.mimeType ?? _inferMime(fileName);
    const allowedMimes = {'image/jpeg', 'image/jpg', 'image/png', 'image/webp'};
    if (!allowedMimes.contains(mimeType)) {
      throw ArgumentError(
        'Invalid file type "$mimeType". Only JPEG, PNG and WebP are allowed.',
      );
    }

    // Client-side size validation (10 MB max)
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.lengthInBytes > maxBytes) {
      final mb = (bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
      throw ArgumentError(
        'File too large (${mb} MB). Maximum allowed is 10 MB.',
      );
    }

    final multipartFile = MultipartFile.fromBytes(
      bytes,
      filename: fileName,
    );

    final formData = FormData.fromMap({'file': multipartFile});

    final response = await _dio.post(
      '/wardrobe/upload',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    return response.data as Map<String, dynamic>;
  }

  String _inferMime(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    const mimeMap = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
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
