import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/routes/app_routes.dart';
import '../../shared/models/user_model.dart';
import '../values/api_endpoints.dart';
import '../values/app_constants.dart';
import 'api_client.dart';

class AuthService extends GetxService {
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final isLoading = false.obs;
  final isAuthenticated = false.obs;
  final user = Rxn<AppUser>();

  Future<AuthService> init() async {
    final token = await _readPersistedToken();
    if (token != null && token.isNotEmpty) {
      _apiClient.setToken(token);
      isAuthenticated.value = true;
      await _restoreCachedUser();
      await loadProfile();
    }
    return this;
  }

  Future<bool> login(String username, String password) async {
    isLoading.value = true;
    try {
      if (kDebugMode) {
        debugPrint('[AuthService] login baseUrl=${_apiClient.baseUrl}');
      }
      final credentials = {
        'username': username,
        'password': password,
      };
      final response = await _createSession(credentials);

      final responseData = response.data;
      if (responseData is! Map ||
          responseData['access_token'] is! String ||
          (responseData['access_token'] as String).isEmpty) {
        throw const ApiException('登录响应中缺少有效令牌');
      }
      final token = responseData['access_token'] as String;
      _apiClient.setToken(token);
      isAuthenticated.value = true;
      await _persistToken(token);
      final profileLoaded = await loadProfile();
      if (!profileLoaded && !isAuthenticated.value) {
        _apiClient.setToken(null);
        return false;
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] login failed: $error');
      }
      Get.snackbar('登录失败', error.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> register(String username, String email, String password) async {
    isLoading.value = true;
    try {
      await _apiClient.post(
        ApiEndpoints.register,
        data: {
          'username': username,
          'email': email,
          'password': password,
        },
      );
      return login(username, password);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] register failed: $error');
      }
      Get.snackbar('注册失败', error.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> loadProfile() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.profile);
      user.value = AppUser.fromJson(response.data);
      isAuthenticated.value = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          AppConstants.userKey, jsonEncode(user.value!.toJson()));
      return true;
    } catch (error) {
      // A temporary NAS/network failure must not erase a valid local
      // session. Only a server-confirmed 401 means the token is invalid.
      if (error is ApiException && error.statusCode == 401) {
        await logout(navigate: false);
      } else if (user.value != null) {
        isAuthenticated.value = true;
      }
      return false;
    }
  }

  Future<void> _restoreCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString(AppConstants.userKey);
    if (rawUser == null || rawUser.isEmpty) return;
    try {
      final decoded = jsonDecode(rawUser);
      if (decoded is Map<String, dynamic>) {
        user.value = AppUser.fromJson(decoded);
        isAuthenticated.value = true;
      }
    } catch (_) {
      await prefs.remove(AppConstants.userKey);
    }
  }

  Future<dio.Response<dynamic>> _createSession(
    Map<String, String> credentials,
  ) async {
    try {
      return await _apiClient.post(ApiEndpoints.session, data: credentials);
    } on ApiException catch (error) {
      // Older NAS deployments predate /auth/session. Prefer the current route
      // because some reverse proxies treat paths ending in /login specially.
      const fallbackStatuses = {404, 405};
      if (!fallbackStatuses.contains(error.statusCode)) rethrow;
      if (kDebugMode) {
        debugPrint(
          '[AuthService] ${ApiEndpoints.session} returned '
          '${error.statusCode}; retrying ${ApiEndpoints.login}',
        );
      }
      return _apiClient.post(ApiEndpoints.login, data: credentials);
    }
  }

  Future<String?> _readPersistedToken() async {
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    String? token = isWindows ? await _readFallbackTokenBestEffort() : null;

    if (token == null || token.isEmpty) {
      try {
        token = await _secureStorage.read(key: AppConstants.tokenKey);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[AuthService] secure token read failed: $error');
        }
      }
    } else {
      await _writeSecureTokenBestEffort(token);
    }

    if (token != null && token.isNotEmpty && isWindows) {
      await _writeFallbackTokenBestEffort(token);
    }
    return token;
  }

  Future<String?> _readFallbackTokenBestEffort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.tokenKey);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] fallback token read failed: $error');
      }
      return null;
    }
  }

  Future<void> _persistToken(String token) async {
    await _writeSecureTokenBestEffort(token);

    // The Windows secure-storage backend has changed locations between plugin
    // versions. Keep a durable app-local fallback so upgrades do not sign the
    // user out when the old encrypted store cannot be migrated.
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _writeFallbackTokenBestEffort(token);
    }
  }

  Future<void> _writeFallbackTokenBestEffort(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.tokenKey, token);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] fallback token write failed: $error');
      }
    }
  }

  Future<void> _writeSecureTokenBestEffort(String token) async {
    try {
      await _secureStorage.write(key: AppConstants.tokenKey, value: token);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] secure token write failed: $error');
      }
    }
  }

  Future<void> logout({bool navigate = true}) async {
    try {
      await _secureStorage.delete(key: AppConstants.tokenKey);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] secure token delete failed: $error');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
    _apiClient.setToken(null);
    isAuthenticated.value = false;
    user.value = null;

    if (navigate) {
      Get.offAllNamed(AppRoutes.login);
    }
  }
}
