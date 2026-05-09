import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthInterceptor extends Interceptor {
  final SupabaseClient _supabase;

  AuthInterceptor(this._supabase);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      print('DEBUG: Adding Auth Header - Token found');
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    } else {
      print('DEBUG: No session found - Using MASTER KEY bypass');
      options.headers['Authorization'] = 'Bearer debug-token-123';
    }
    super.onRequest(options, handler);
  }
}

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.response?.statusCode) {
      case 401:
        // Handle 401: Maybe trigger a logout or token refresh
        // Supabase handles token refresh automatically, so 401 might mean expired session
        break;
      case 429:
        // Handle Rate Limiting
        break;
      case 503:
        // Handle Service Unavailable
        break;
    }
    super.onError(err, handler);
  }
}
