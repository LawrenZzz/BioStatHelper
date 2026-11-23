import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' as getx;

import '../values/app_config.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.type,
    this.requestUri,
  });

  final String message;
  final int? statusCode;
  final DioExceptionType? type;
  final Uri? requestUri;

  bool get isTimeout => type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout;

  @override
  String toString() => message;
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  String? _token;

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && isBackendUrl(options.uri.toString())) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        if (kDebugMode) {
          options.extra['requestStartedAt'] = DateTime.now();
          debugPrint('[ApiClient][REQ] ${options.method} ${options.uri} '
              'connectTimeout=${options.connectTimeout} '
              'sendTimeout=${options.sendTimeout} receiveTimeout=${options.receiveTimeout}');
          if (options.data != null) {
            debugPrint('[ApiClient][REQ_BODY] ${_debugDataSummary(options.data)}');
          }
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint('[ApiClient] RESPONSE ${response.requestOptions.method} '
              '${response.requestOptions.uri} status=${response.statusCode} '
              'elapsed=${response.requestOptions.extra['requestStartedAt'] == null ? 'n/a' : DateTime.now().difference(response.requestOptions.extra['requestStartedAt'] as DateTime)}');
        }
        return handler.next(response);
      },
      onError: (error, handler) {
        if (kDebugMode) {
          debugPrint(
            '[ApiClient] ERROR ${error.requestOptions.method} '
            '${error.requestOptions.uri} '
            'type=${error.type} message=${error.message} '
            'status=${error.response?.statusCode}',
          );
          if (error.error != null) {
            debugPrint('[ApiClient] raw error=${error.error}');
          }
        }
        _handleError(error);
        return handler.next(error);
      },
    ));
  }

  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  String get baseUrl => _dio.options.baseUrl;

  bool isBackendUrl(String url) {
    final base = Uri.parse(baseUrl);
    final target = base.resolve(url);
    return target.scheme == base.scheme &&
        target.host == base.host && target.port == base.port;
  }

  String absoluteUrl(String path) {
    final apiBase = Uri.parse(_dio.options.baseUrl);
    final origin = '${apiBase.scheme}://${apiBase.authority}';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/static/') || path.startsWith('/admin/')) {
      return '$origin$path';
    }
    if (path.startsWith('/api/')) {
      return '$origin$path';
    }
    if (!path.startsWith('/')) {
      return '$origin/$path';
    }
    return '$origin/api/v1$path';
  }

  String _debugDataSummary(dynamic data) {
    if (data == null) return 'null';
    if (data is String) {
      return data.length > 500 ? '${data.substring(0, 500)}…' : data;
    }
    if (data is Map) {
      return 'Map(keys=${data.keys.join(',')}, length=${data.length})';
    }
    if (data is List) return 'List(length=${data.length})';
    return data.toString();
  }

  void _handleError(DioException error) {
    String message = '请求失败';

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        message = '连接超时';
        break;
      case DioExceptionType.sendTimeout:
        message = '发送超时';
        break;
      case DioExceptionType.receiveTimeout:
        message = '接收超时';
        break;
      case DioExceptionType.badResponse:
        message = _handleStatusCode(error.response?.statusCode);
        break;
      case DioExceptionType.cancel:
        message = '请求已取消';
        break;
      case DioExceptionType.connectionError:
        message = '连接错误：无法连接到 ${error.requestOptions.uri.host}';
        break;
      default:
        message = '网络错误';
    }

    if (getx.Get.context != null) getx.Get.snackbar('错误', message);
  }

  String _handleStatusCode(int? statusCode) {
    switch (statusCode) {
      case 400:
        return '请求参数错误';
      case 401:
        return '未授权，请重新登录';
      case 403:
        return '拒绝访问';
      case 404:
        return '请求资源不存在';
      case 500:
        return '服务器内部错误';
      default:
        return '请求失败';
    }
  }

  String _messageFromError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return error.message ?? '请求失败';
  }

  // GET请求
  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }

  Future<String> getText(String path) async {
    try {
      final response = await _dio.get(
        absoluteUrl(path),
        options: Options(responseType: ResponseType.plain),
      );
      return response.data?.toString() ?? '';
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }

  // POST请求
  Future<Response> post(
    String path, {
    dynamic data,
    Duration? timeout,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        options: timeout == null
            ? null
            : Options(
                sendTimeout: timeout,
                receiveTimeout: timeout,
                connectTimeout: timeout,
              ),
      );
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }

  Future<Response> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    Map<String, dynamic>? fields,
    Duration? timeout,
  }) async {
    try {
      final formData = FormData.fromMap({
        ...?fields,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      return await _dio.post(
        path,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }

  // PUT请求
  Future<Response> put(String path, {dynamic data}) async {
    try {
      return await _dio.put(path, data: data);
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }

  /// 下载原始字节（附件）。path 需指向返回二进制内容的端点。
  Future<List<int>> downloadBytes(String path) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? <int>[];
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }

  // DELETE请求
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
      );
    } on DioException catch (e) {
      throw ApiException(
        _messageFromError(e),
        statusCode: e.response?.statusCode,
        type: e.type,
        requestUri: e.requestOptions.uri,
      );
    }
  }
}
