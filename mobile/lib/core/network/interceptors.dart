import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Attaches Supabase JWT to every outgoing request.
/// Falls back to a debug token when no session is active (local dev mode).
class AuthInterceptor extends Interceptor {
  final SupabaseClient _supabase;

  AuthInterceptor(this._supabase);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    } else {
      // Local dev bypass — backend accepts any token in dev mode
      options.headers['Authorization'] = 'Bearer debug-token-123';
    }
    super.onRequest(options, handler);
  }
}

/// Handles 401 by refreshing the Supabase session before retrying.
/// Maps common HTTP errors to user-friendly messages.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;

    if (statusCode == 401) {
      // Attempt token refresh
      try {
        await Supabase.instance.client.auth.refreshSession();

        // Retry the original request with the new token
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer ${session.accessToken}';

          final dio = Dio();
          final response = await dio.fetch(opts);
          return handler.resolve(response);
        }
      } catch (_) {
        // Refresh failed — propagate the original 401
      }
    }

    // Map common errors for better user-facing messages
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: 'Connection timed out. Please check your internet.',
          type: err.type,
        ),
      );
    }

    if (err.type == DioExceptionType.connectionError) {
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: 'Cannot reach server. Please try again later.',
          type: err.type,
        ),
      );
    }

    super.onError(err, handler);
  }
}
