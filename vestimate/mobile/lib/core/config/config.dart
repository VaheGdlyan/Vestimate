import 'package:flutter/foundation.dart';

class AppConfig {
  // Auto-selects the correct base URL:
  //   - Chrome / Web build  → 127.0.0.1 (same machine)
  //   - Physical phone      → LAN IP (phone talks to computer over Wi-Fi)
  // If your Wi-Fi IP changes, update _lanIp below and hot-restart.
  static const String _lanIp = '10.219.8.22';

  static String get apiBaseUrl =>
      kIsWeb ? 'http://127.0.0.1:8888/v1' : 'http://$_lanIp:8888/v1';

  static const String supabaseUrl = 'https://xkruowqfzucoyornykot.supabase.co';

  // Supabase Anon Key
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrcnVvd3FmenVjb3lvcm55a290Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3MzAxMzYsImV4cCI6MjA5MzMwNjEzNn0.qiJiGQuMyFsMRhX2Oie7wRAwF6vmHd7SQVJoZJ5iLuU';
}

