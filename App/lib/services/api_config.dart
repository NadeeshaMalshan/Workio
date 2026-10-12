import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  /// Optional runtime override if dynamic reconfiguration is needed
  static String? customBaseUrl;

  static String _resolveHost(String url) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return url.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
    }
    return url;
  }

  /// Retrieves backend base URL dynamically:
  /// 1. Programmatic override (customBaseUrl)
  /// 2. Value from .env file via flutter_dotenv
  static String? _getEnv(String key) {
    if (dotenv.isInitialized) {
      return dotenv.env[key];
    }
    return null;
  }

  /// 3. Fallback to compile-time environment variable (--dart-define)
  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.trim().isNotEmpty) {
      return _resolveHost(customBaseUrl!.trim());
    }
    final envUrl = _getEnv('BACKEND_URL');
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      return _resolveHost(envUrl.trim());
    }
    const defineUrl = String.fromEnvironment('BACKEND_URL');
    if (defineUrl.isNotEmpty) {
      return _resolveHost(defineUrl.trim());
    }
    return _resolveHost('http://localhost:5237');
  }

  // Endpoints
  static String get googleAuthUrl => '$baseUrl/api/auth/google';
  static String get onboardingUrl => '$baseUrl/api/auth/onboarding';

  /// Google OAuth Client ID loaded dynamically from .env or compile-time define
  static String get googleClientId {
    final envClientId = _getEnv('GOOGLE_CLIENT_ID');
    if (envClientId != null && envClientId.trim().isNotEmpty) {
      return envClientId.trim();
    }
    return const String.fromEnvironment('GOOGLE_CLIENT_ID');
  }

  /// OneSignal App ID loaded from .env or compile-time define
  static String get onesignalAppId {
    final envId = _getEnv('ONESIGNAL_APP_ID');
    if (envId != null && envId.trim().isNotEmpty) {
      return envId.trim();
    }
    const defineId = String.fromEnvironment('ONESIGNAL_APP_ID');
    if (defineId.isNotEmpty) {
      return defineId;
    }
    return 'b7e6df63-34ca-4bbd-8889-b8844c9b579b';
  }

  /// LangGraph AI Agent Backend URL
  static String get agentBackendUrl {
    final envUrl = _getEnv('AGENT_BACKEND_URL');
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      return _resolveHost(envUrl.trim());
    }
    const defineUrl = String.fromEnvironment('AGENT_BACKEND_URL');
    if (defineUrl.isNotEmpty) {
      return _resolveHost(defineUrl.trim());
    }
    return _resolveHost('http://localhost:8001');
  }
}

