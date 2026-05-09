import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/core/network/dio_provider.dart';

part 'wardrobe_repository.g.dart';

class WardrobeRepository {
  final Dio _dio;

  WardrobeRepository(this._dio);

  Future<Map<String, dynamic>> uploadGarment(File image) async {
    final fileName = image.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        image.path,
        filename: fileName,
      ),
    });

    final response = await _dio.post(
      '/wardrobe/upload',
      data: formData,
    );

    return response.data;
  }

  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    final response = await _dio.get('/tasks/$taskId');
    return response.data;
  }

  Future<List<Map<String, dynamic>>> fetchWardrobeItems({String? category}) async {
    try {
      final response = await _dio.get(
        '/wardrobe/items',
        queryParameters: category != null ? {'category': category} : null,
      );
      final data = List<Map<String, dynamic>>.from(response.data['items']);
      
      // Persist to Hive for offline support
      if (category == null) { // Only cache the "All" view
        final box = Hive.box('wardrobe_cache');
        await box.put('items', data);
      }
      
      return data;
    } catch (e) {
      // If offline, return from cache
      final box = Hive.box('wardrobe_cache');
      final cached = box.get('items');
      if (cached != null) {
        return List<Map<String, dynamic>>.from(cached);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getTodayRecommendation() async {
    final response = await _dio.get('/recommendations/today');
    return response.data;
  }

  Future<void> sendFeedback(String itemId, String action) async {
    await _dio.post('/feedback', data: {
      'item_id': itemId,
      'action': action,
    });
  }
}

@riverpod
WardrobeRepository wardrobeRepository(WardrobeRepositoryRef ref) {
  return WardrobeRepository(ref.watch(dioProvider));
}
