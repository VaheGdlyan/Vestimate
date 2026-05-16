import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vestimate/core/config/config.dart';
import 'package:vestimate/core/network/interceptors.dart';

part 'dio_provider.g.dart';

@riverpod
Dio dio(DioRef ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  final supabase = Supabase.instance.client;
  
  dio.interceptors.addAll([
    AuthInterceptor(supabase),
    ErrorInterceptor(),
    LogInterceptor(requestBody: true, responseBody: true), // For debugging
  ]);

  return dio;
}
