import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/video_model.dart';
import 'api_client.dart';
import 'auth_service.dart';

class StudyCacheEntry {
  const StudyCacheEntry(
      {required this.video,
      required this.complete,
      required this.receivedBytes,
      this.totalBytes,
      this.layout = 'single',
      this.attachments = const []});
  final Video video;
  final bool complete;
  final int receivedBytes;
  final int? totalBytes;
  final String layout;
  final List<StudyCachedAttachment> attachments;
}

/// IDs must identify the representation/quality, not an expiring CDN URL.
class StudyCacheTrack {
  const StudyCacheTrack(
      {required this.id, required this.url, this.headers = const {}});
  final String id;
  final String url;
  final Map<String, String> headers;
}

class StudyCacheAttachment {
  const StudyCacheAttachment.remote(
      {required this.id,
      required this.kind,
      required this.extension,
      required this.url,
      this.title = '',
      this.headers = const {}})
      : text = null;
  const StudyCacheAttachment.text(
      {required this.id,
      required this.kind,
      required this.extension,
      required this.text,
      this.title = ''})
      : url = null,
        headers = const {};
  final String id;
  final String kind;
  final String extension;
  final String title;
  final String? url;
  final String? text;
  final Map<String, String> headers;
}

class StudyCachedAttachment {
  const StudyCachedAttachment(
      {required this.id,
      required this.kind,
      required this.extension,
      required this.title,
      required this.path,
      required this.bytes});
  final String id;
  final String kind;
  final String extension;
  final String title;
  final String path;
  final int bytes;
}

class StudyCachedPlayback {
  const StudyCachedPlayback(
      {required this.mediaUri,
      this.audioPath,
      this.segments = const [],
      this.attachments = const []});

  /// Local file or a byte-length-escaped mpv EDL. Never a muxed DASH file.
  final String mediaUri;
  final String? audioPath;
  final List<String> segments;
  final List<StudyCachedAttachment> attachments;
  String get videoPath => mediaUri;
  List<VideoSidecar> get sidecars => [
        for (final item in attachments)
          VideoSidecar(
              id: int.parse(
                  sha256
                      .convert(utf8.encode(item.id))
                      .toString()
                      .substring(0, 12),
                  radix: 16),
              fileName: '${item.id}${item.extension}',
              extension: item.extension,
              kind: item.kind,
              title: item.title,
              url: File(item.path).uri.toString())
      ];
}

class _Transfer {
  _Transfer(this.scope);
  final String scope;
  final token = CancelToken();
  final done = Completer<void>();
}

class StudyMediaCache {
  StudyMediaCache(
      {Dio? dio,
      ApiClient? api,
      Future<Directory> Function()? rootDirectory,
      String? Function()? scope})
      : _api = api ?? ApiClient(),
        _dio = dio ?? Dio(),
        _rootDirectory = rootDirectory ?? getApplicationSupportDirectory,
        _scopeOverride = scope {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.followRedirects = false;
    _dio.options.headers.removeWhere((name, _) => {
          'authorization',
          'cookie',
          'range',
          'if-range'
        }.contains(name.toLowerCase()));
  }

  static final StudyMediaCache instance = StudyMediaCache();
  final ApiClient _api;
  final Dio _dio;
  final Future<Directory> Function() _rootDirectory;
  final String? Function()? _scopeOverride;
  final progress = <String, double>{}.obs;
  final errors = <String, String>{}.obs;
  final attachmentErrors = <String, String>{}.obs;
  final revision = 0.obs;
  final _activeKeys = <String>{}.obs;
  final _active = <String, _Transfer>{};
  final _removing = <String>{};
  Worker? _authWorker;
  AuthService? _watchedAuth;

  String? get scopeKey {
    final override = _scopeOverride;
    if (override != null) return override();
    final userId = Get.isRegistered<AuthService>()
        ? Get.find<AuthService>().user.value?.id
        : null;
    return userId == null
        ? null
        : sha256.convert(utf8.encode('${_api.baseUrl}:$userId')).toString();
  }

  String _fileKey(Video video) => sha256
      .convert(utf8.encode(
          '${video.source}:${video.id}:${video.sourceData['cid'] ?? ''}'))
      .toString();

  // Keep on-disk names compatible; only in-memory keys need the account prefix.
  String keyFor(Video video) =>
      '${scopeKey ?? 'signed-out'}:${_fileKey(video)}';

  void _watchAccount() {
    if (_scopeOverride != null || !Get.isRegistered<AuthService>()) return;
    final auth = Get.find<AuthService>();
    if (identical(auth, _watchedAuth)) return;
    _authWorker?.dispose();
    _watchedAuth = auth;
    _authWorker = ever(auth.user, (_) {
      for (final transfer in _active.values) {
        if (transfer.scope != scopeKey) {
          transfer.token.cancel('Account changed');
        }
      }
      revision.value++;
    });
  }

  String _requireScope() {
    if (kIsWeb) throw StateError('浏览器暂不支持离线缓存');
    _watchAccount();
    final scope = scopeKey;
    if (scope == null) throw StateError('请先登录再使用离线缓存');
    return scope;
  }

  void _checkScope(String scope) {
    if (scopeKey != scope) throw StateError('账号或服务器已切换，请刷新缓存列表');
  }

  void _checkTransfer(_Transfer transfer) {
    _checkScope(transfer.scope);
    if (transfer.token.isCancelled) throw transfer.token.cancelError!;
  }

  Future<Directory> _directory(String scope) async {
    final root = await _rootDirectory();
    _checkScope(scope);
    return Directory('${root.path}/study_cache/$scope').create(recursive: true);
  }

  Future<Map<String, dynamic>> _manifest(File file) async {
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Map<String, dynamic> _details(Map<String, dynamic> manifest) =>
      manifest['_cache'] is Map
          ? Map<String, dynamic>.from(manifest['_cache'])
          : {};

  Future<void> _saveManifest(
      File file, Video video, Map<String, dynamic> details) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        jsonEncode({...video.toJson(), '_cache': details}),
        flush: true);
    await temporary.rename(file.path);
  }

  Future<String?> localPath(Video video) async {
    final playback = await localPlayback(video);
    // Old players only accept one URI. Do not silently play DASH without audio.
    return playback?.audioPath == null ? playback?.mediaUri : null;
  }

  Future<StudyCachedPlayback?> localPlayback(Video video) async {
    if (kIsWeb) return null;
    final scope = _requireScope();
    final directory = await _directory(scope);
    final key = _fileKey(video);
    final manifest = await _manifest(File('${directory.path}/$key.json'));
    if (manifest.isEmpty) return null;
    final details = _details(manifest);
    if (details['version'] == 2) {
      return _bundlePlayback(video, scope, directory, details);
    }
    final media = File('${directory.path}/$key.media');
    if (!await media.exists()) return null;
    final length = await media.length();
    final expected = details['total_bytes'];
    _checkScope(scope);
    if (length <= 0 || (expected is int && length != expected)) return null;
    if (details.isNotEmpty &&
        details['complete'] != true &&
        expected != length) {
      return null;
    }
    final attachments = await localAttachments(video);
    _checkScope(scope);
    return StudyCachedPlayback(mediaUri: media.path, attachments: attachments);
  }

  Map<String, String> _safeHeaders(
      Video video, Uri uri, Map<String, String> supplied) {
    final result = <String, String>{};
    for (final entry in supplied.entries) {
      final name = entry.key.toLowerCase();
      // No caller cookies, bearer tokens, or range directives reach a CDN.
      if ({'user-agent', 'referer', 'accept'}.contains(name)) {
        result[entry.key] = entry.value;
      }
    }
    if (video.source == 'nas' &&
        _api.isBackendUrl(uri.toString()) &&
        _api.token != null) {
      result['Authorization'] = 'Bearer ${_api.token}';
    }
    result['Accept-Encoding'] = 'identity';
    return result;
  }

  String? _validator(Map<String, dynamic> details) {
    final etag = details['etag'];
    if (etag is String && etag.startsWith('"') && etag.endsWith('"')) {
      return etag;
    }
    final modified = details['last_modified'];
    if (modified is String) {
      try {
        HttpDate.parse(modified);
        return modified;
      } on FormatException {/* No usable validator. */}
    }
    return null;
  }

  Future<void> download(
      Video video, String url, Map<String, String> headers) async {
    final initialScope = _requireScope();
    final completed = await _runTransfer(video, (scope, key, transfer) async {
      final directory = await _directory(scope);
      final basename = '${directory.path}/${_fileKey(video)}';
      final old = _details(await _manifest(File('$basename.json')));
      if (old['version'] == 2) {
        throw StateError('多轨缓存请使用原轨道信息重试');
      }
      await _downloadFile(video, url, headers, transfer, basename,
          onProgress: (value) => progress[key] = value);
    });
    if (completed && video.sidecars.isNotEmpty) {
      try {
        await cacheAttachments(
            video,
            [
              for (final sidecar in video.sidecars)
                StudyCacheAttachment.remote(
                    id: '${sidecar.kind}:${sidecar.id}',
                    kind: sidecar.kind,
                    extension: sidecar.extension,
                    title: sidecar.title,
                    url: sidecar.url)
            ],
            expectedScope: initialScope);
      } catch (_) {
        // Optional attachments have a separate visible error/retry state.
      }
    }
  }

  Future<bool> _runTransfer(Video video,
      Future<void> Function(String scope, String key, _Transfer transfer) task,
      {bool attachments = false}) async {
    final scope = _requireScope();
    final mediaKey = '$scope:${_fileKey(video)}';
    final key = attachments ? '$mediaKey:attachments' : mediaKey;
    if (_active.containsKey(key) || _removing.contains(mediaKey)) return false;
    final transfer = _Transfer(scope);
    _active[key] = transfer;
    _activeKeys.add(key);
    if (!attachments) progress[key] = 0;
    final errorState = attachments ? attachmentErrors : errors;
    errorState.remove(mediaKey);
    revision.value++;
    try {
      await task(scope, key, transfer);
      _checkTransfer(transfer);
      if (!attachments) progress[key] = 1;
      return true;
    } catch (error) {
      if (!transfer.token.isCancelled) {
        errorState[mediaKey] =
            error is DioException ? '缓存失败（${error.type.name}），可重试' : '$error';
        rethrow;
      }
      return false;
    } finally {
      _active.remove(key);
      _activeKeys.remove(key);
      transfer.done.complete();
      revision.value++;
    }
  }

  Future<void> _downloadFile(Video video, String url,
      Map<String, String> headers, _Transfer transfer, String basename,
      {required void Function(double) onProgress,
      bool separateTrack = false}) async {
    final scope = transfer.scope;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'\.(mpd|m3u8)$', caseSensitive: false).hasMatch(uri.path) ||
        (!separateTrack && uri.path.toLowerCase().endsWith('.m4s'))) {
      throw StateError('仅支持完整的 HTTP 视频文件，不支持播放清单或分离音视频流');
    }
    final part = File('$basename.part');
    final destination = File('$basename.media');
    final manifest = File('$basename.json');
    var details = _details(await _manifest(manifest));
    if (await _verifiedMedia(basename)) {
      onProgress(1);
      return;
    }
    if (await destination.exists()) await destination.delete();
    await _saveManifest(
        manifest, video, {...details, 'version': 1, 'complete': false});
    final requestHeaders = _safeHeaders(video, uri, headers);
    var offset = await part.exists() ? await part.length() : 0;
    final validator = _validator(details);
    final previousTotal = details['total_bytes'];
    if (validator == null ||
        (previousTotal is int && offset >= previousTotal)) {
      offset = 0;
    }
    Response<ResponseBody> response;
    while (true) {
      _checkTransfer(transfer);
      response = await _dio.get<ResponseBody>(url,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            headers: {
              ...requestHeaders,
              if (offset > 0) ...{
                'Range': 'bytes=$offset-',
                'If-Range': validator!
              }
            },
            validateStatus: (status) => status == 200 || status == 206,
          ),
          cancelToken: transfer.token);
      _checkScope(scope);
      final sameResource = validator == null ||
          (details['etag'] == validator
              ? response.headers.value('etag') == validator
              : response.headers.value('last-modified') == validator);
      final rangeTotal = int.tryParse(
          (response.headers.value('content-range') ?? '').split('/').last);
      if (offset > 0 &&
          response.statusCode == 206 &&
          (!sameResource ||
              (previousTotal is int && rangeTotal != previousTotal))) {
        await response.data!.stream.listen((_) {}).cancel();
        offset = 0;
        continue;
      }
      break;
    }
    final contentType =
        response.headers.value('content-type')?.toLowerCase() ?? '';
    if (contentType.contains('mpegurl') ||
        contentType.contains('dash+xml') ||
        contentType.contains('text/') ||
        contentType.contains('json')) {
      await response.data!.stream.listen((_) {}).cancel();
      throw StateError('服务器未返回完整视频文件，不能缓存');
    }
    final bodyLength =
        int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
    int total;
    if (response.statusCode == 206) {
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers.value('content-range') ?? '');
      if (range == null ||
          int.parse(range[1]!) != offset ||
          int.parse(range[2]!) != int.parse(range[3]!) - 1 ||
          bodyLength != int.parse(range[2]!) - offset + 1) {
        await response.data!.stream.listen((_) {}).cancel();
        throw StateError('服务器返回的续传范围不完整或不正确，请重试');
      }
      total = int.parse(range[3]!);
    } else {
      offset = 0;
      total = bodyLength;
    }
    if (total <= 0 || bodyLength <= 0) {
      await response.data!.stream.listen((_) {}).cancel();
      throw StateError('服务器未提供可靠文件长度，无法验证完整缓存');
    }
    details = {
      'version': 1,
      'complete': false,
      'total_bytes': total,
      'etag': response.headers.value('etag'),
      'last_modified': response.headers.value('last-modified')
    };
    await _saveManifest(manifest, video, details);
    _checkScope(scope);
    _checkTransfer(transfer);
    var received = offset;
    final sink =
        part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response.data!.stream) {
        _checkScope(scope);
        _checkTransfer(transfer);
        if (received + chunk.length > total) {
          throw StateError('视频数据超过声明长度，缓存未完成');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress((received / total).clamp(0.0, 0.999999));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    _checkTransfer(transfer);
    _checkScope(scope);
    if (received != total || await part.length() != total) {
      throw StateError('缓存未下载完整，请继续或重试');
    }
    await part.rename(destination.path);
    await _saveManifest(manifest, video, {...details, 'complete': true});
    onProgress(1);
  }

  Future<bool> _verifiedMedia(String basename) async {
    final file = File('$basename.media');
    if (!await file.exists()) return false;
    final manifest = await _manifest(File('$basename.json'));
    if (manifest.isEmpty) return false;
    final details = _details(manifest);
    final length = await file.length();
    return length > 0 &&
        (details.isEmpty ||
            (details['complete'] == true && details['total_bytes'] == length));
  }

  String _trackBase(Directory directory, Video video, String id) =>
      '${directory.path}/${_fileKey(video)}.track.${sha256.convert(utf8.encode(id))}';

  List<Map<String, dynamic>> _tracks(Map<String, dynamic> details) {
    final rows = details['tracks'];
    if (rows is! List || rows.isEmpty || rows.length > 256) return [];
    final result = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          (row['id'] as String).isEmpty ||
          !ids.add(row['id'])) {
        return [];
      }
      result.add(Map<String, dynamic>.from(row));
    }
    final roles = result.map((row) => row['role']).toList();
    if (details['layout'] == 'dash') {
      return roles.length == 2 && roles[0] == 'video' && roles[1] == 'audio'
          ? result
          : [];
    }
    return details['layout'] == 'segments' &&
            roles.every((role) => role == 'segment')
        ? result
        : [];
  }

  Future<StudyCachedPlayback?> _bundlePlayback(Video video, String scope,
      Directory directory, Map<String, dynamic> details) async {
    final tracks = _tracks(details);
    if (details['complete'] != true || tracks.isEmpty) return null;
    final paths = <String>[];
    for (final track in tracks) {
      final base = _trackBase(directory, video, track['id']);
      if (!await _verifiedMedia(base)) return null;
      paths.add('$base.media');
    }
    final attachments = await localAttachments(video);
    _checkScope(scope);
    if (details['layout'] == 'dash') {
      return StudyCachedPlayback(
          mediaUri: paths.first,
          audioPath: paths.last,
          attachments: attachments);
    }
    return StudyCachedPlayback(
        mediaUri: paths.length == 1
            ? paths.single
            : 'edl://${paths.map((path) => '%${utf8.encode(path).length}%$path').join(';')}',
        segments: List.unmodifiable(paths),
        attachments: attachments);
  }

  Future<StudyCachedPlayback?> localBundle(Video video) => localPlayback(video);

  /// Download complete representations, not MPD manifests or isolated fragments.
  /// Callers re-resolve URLs on retry and use a stable quality/codec identity.
  Future<void> downloadBundle(
      Video video, List<String> segments, Map<String, String> headers,
      {String? audioUrl,
      List<StudyCacheAttachment> attachments = const [],
      String representationId = 'default',
      String? expectedScope}) async {
    if (expectedScope != null) _checkScope(expectedScope);
    if (segments.isEmpty ||
        segments.length > 256 ||
        (audioUrl != null && segments.length != 1) ||
        representationId.isEmpty) {
      throw ArgumentError(
          'A bundle needs ordered segments or exactly one DASH video/audio pair');
    }
    final tracks = [
      for (var i = 0; i < segments.length; i++)
        StudyCacheTrack(
            id: '$representationId:${audioUrl == null ? 'segment' : 'video'}:$i',
            url: segments[i],
            headers: headers),
      if (audioUrl != null)
        StudyCacheTrack(
            id: '$representationId:audio', url: audioUrl, headers: headers)
    ];
    final scope = _requireScope();
    final completed = await _runTransfer(video, (scope, key, transfer) async {
      final directory = await _directory(scope);
      final manifest = File('${directory.path}/${_fileKey(video)}.json');
      final old = _details(await _manifest(manifest));
      if (segments.length == 1 && audioUrl == null && old['version'] != 2) {
        await _downloadFile(video, segments.single, headers, transfer,
            '${directory.path}/${_fileKey(video)}',
            onProgress: (value) => progress[key] = value);
        return;
      }
      final details = {
        'version': 2,
        'layout': audioUrl == null ? 'segments' : 'dash',
        'complete': false,
        'tracks': [
          for (var i = 0; i < tracks.length; i++)
            {
              'id': tracks[i].id,
              'role': audioUrl == null
                  ? 'segment'
                  : i == 0
                      ? 'video'
                      : 'audio'
            }
        ]
      };
      await _saveManifest(manifest, video, details);
      for (var i = 0; i < tracks.length; i++) {
        _checkTransfer(transfer);
        final track = tracks[i];
        await _downloadFile(video, track.url, track.headers, transfer,
            _trackBase(directory, video, track.id),
            separateTrack: audioUrl != null,
            onProgress: (value) => progress[key] =
                ((i + value) / tracks.length).clamp(0.0, 0.999999));
      }
      _checkTransfer(transfer);
      await _saveManifest(manifest, video, {...details, 'complete': true});
    });
    final allAttachments = <String, StudyCacheAttachment>{
      if (video.source == 'nas')
        for (final sidecar in video.sidecars)
          '${sidecar.kind}:${sidecar.id}': StudyCacheAttachment.remote(
              id: '${sidecar.kind}:${sidecar.id}',
              kind: sidecar.kind,
              extension: sidecar.extension,
              title: sidecar.title,
              url: sidecar.url),
      for (final attachment in attachments) attachment.id: attachment,
    };
    if (completed && allAttachments.isNotEmpty) {
      try {
        await cacheAttachments(video, allAttachments.values.toList(),
            expectedScope: scope);
      } catch (_) {
        // Media remains usable; optional attachment failures are separate.
      }
    }
  }

  static const _attachmentLimit = 8 * 1024 * 1024;
  static const _extensions = {
    'subtitle': {'.srt', '.vtt', '.ass', '.ssa', '.json'},
    'danmaku': {'.xml', '.json', '.ass', '.ssa'}
  };

  String _attachmentPath(Directory directory, Video video, String id,
          String digest, String extension) =>
      '${directory.path}/${_fileKey(video)}.attachment.${sha256.convert(utf8.encode(id))}.$digest$extension';

  Future<List<StudyCachedAttachment>> localAttachments(Video video) async {
    final scope = _requireScope();
    final directory = await _directory(scope);
    final index = await _manifest(
        File('${directory.path}/${_fileKey(video)}.attachments.json'));
    final rows = index['attachments'];
    final result = <StudyCachedAttachment>[];
    if (rows is! List || rows.length > 64) return result;
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          row['digest'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['digest']) ||
          !(_extensions[row['kind']]?.contains(row['extension']) ?? false) ||
          row['bytes'] is! int ||
          row['bytes'] <= 0 ||
          row['bytes'] > _attachmentLimit) {
        continue;
      }
      final file = File(_attachmentPath(
          directory, video, row['id'], row['digest'], row['extension']));
      if (!await file.exists() || await file.length() != row['bytes']) continue;
      final bytes = await file.readAsBytes();
      if (sha256.convert(bytes).toString() != row['digest']) continue;
      result.add(StudyCachedAttachment(
          id: row['id'],
          kind: row['kind'],
          extension: row['extension'],
          title: '${row['title'] ?? ''}',
          path: file.path,
          bytes: bytes.length));
    }
    _checkScope(scope);
    return List.unmodifiable(result);
  }

  /// An arbitrary file:// URL is never trusted as a cached sidecar.
  Future<String?> readSidecar(Video video, VideoSidecar sidecar) async {
    final scope = _requireScope();
    final attachments = await localAttachments(video);
    for (final item in attachments) {
      if (File(item.path).uri.toString() == sidecar.url &&
          item.kind == sidecar.kind &&
          item.extension == sidecar.extension) {
        final text = await File(item.path).readAsString();
        _checkScope(scope);
        return text;
      }
    }
    return null;
  }

  Future<List<int>> _attachmentBytes(
      Video video, StudyCacheAttachment item, _Transfer transfer) async {
    final text = item.text;
    if (text != null) return utf8.encode(text);
    final url = _api.absoluteUrl(item.url!);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('附件地址不是有效的 HTTP 地址');
    }
    final response = await _dio.get<ResponseBody>(url,
        options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            headers: _safeHeaders(video, uri, item.headers),
            validateStatus: (status) => status == 200),
        cancelToken: transfer.token);
    final body = response.data!;
    final type = response.headers.value('content-type')?.toLowerCase() ?? '';
    final expected =
        int.tryParse(response.headers.value('content-length') ?? '');
    if (type.contains('html') ||
        (expected != null && (expected <= 0 || expected > _attachmentLimit))) {
      await body.stream.listen((_) {}).cancel();
      throw StateError('附件不是可用文本或超过 8 MiB');
    }
    final bytes = <int>[];
    await for (final chunk in body.stream) {
      _checkTransfer(transfer);
      if (bytes.length + chunk.length > _attachmentLimit) {
        throw StateError('附件超过 8 MiB');
      }
      bytes.addAll(chunk);
    }
    if (expected != null && bytes.length != expected) {
      throw StateError('附件未下载完整');
    }
    return bytes;
  }

  Future<void> cacheAttachments(
      Video video, List<StudyCacheAttachment> attachments,
      {String? expectedScope}) async {
    if (expectedScope != null) _checkScope(expectedScope);
    final ids = <String>{};
    if (attachments.length > 64) {
      throw ArgumentError('At most 64 attachments per video');
    }
    for (final item in attachments) {
      if (item.id.isEmpty ||
          !ids.add(item.id) ||
          !(_extensions[item.kind]?.contains(item.extension) ?? false) ||
          (item.text == null && (item.url == null || item.url!.isEmpty))) {
        throw ArgumentError('Invalid attachment identity, format or content');
      }
    }
    await _runTransfer(video, (scope, key, transfer) async {
      final directory = await _directory(scope);
      final base = '${directory.path}/${_fileKey(video)}';
      if ((await _manifest(File('$base.json'))).isEmpty) {
        throw StateError('请先创建视频缓存任务');
      }
      final indexFile = File('$base.attachments.json');
      final index = await _manifest(indexFile);
      final old = index['attachments'];
      final rows = <String, Map<String, dynamic>>{
        if (old is List)
          for (final row in old.whereType<Map>())
            if (row['id'] is String) row['id']: Map<String, dynamic>.from(row)
      };
      if ({...rows.keys, ...ids}.length > 64) throw StateError('附件数量超过限制');
      for (final item in attachments) {
        _checkTransfer(transfer);
        final bytes = await _attachmentBytes(video, item, transfer);
        if (bytes.isEmpty || bytes.length > _attachmentLimit) {
          throw StateError('附件为空或超过 8 MiB');
        }
        final text = utf8.decode(bytes);
        if (RegExp(r'<!DOCTYPE|<!ENTITY|<html[\s>]', caseSensitive: false)
            .hasMatch(text)) {
          throw StateError('附件包含不支持的 HTML 或 XML 实体');
        }
        _checkTransfer(transfer);
        final digest = sha256.convert(bytes).toString();
        final file = File(
            _attachmentPath(directory, video, item.id, digest, item.extension));
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        _checkTransfer(transfer);
        await temporary.rename(file.path);
        rows[item.id] = {
          'id': item.id,
          'kind': item.kind,
          'extension': item.extension,
          'title': item.title,
          'bytes': bytes.length,
          'digest': digest
        };
        final temporaryIndex = File('${indexFile.path}.tmp');
        await temporaryIndex.writeAsString(
            jsonEncode({'attachments': rows.values.toList()}),
            flush: true);
        _checkTransfer(transfer);
        await temporaryIndex.rename(indexFile.path);
      }
    }, attachments: true);
  }

  bool isCachingAttachments(Video video) =>
      _activeKeys.contains('${keyFor(video)}:attachments');

  bool isDownloading(Video video) => _activeKeys.contains(keyFor(video));
  void pause(Video video) {
    final key = keyFor(video);
    _active[key]?.token.cancel('Paused');
    _active['$key:attachments']?.token.cancel('Paused');
  }

  Future<List<StudyCacheEntry>> entries() async {
    final scope = _requireScope();
    final directory = await _directory(scope);
    final result = <StudyCacheEntry>[];
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final manifest = await _manifest(file);
      if (manifest.isEmpty) continue;
      try {
        final video = Video.fromJson(manifest);
        final basename = '${directory.path}/${_fileKey(video)}';
        if (file.uri.pathSegments.last != '${_fileKey(video)}.json') continue;
        final details = _details(manifest);
        final playback = await localPlayback(video);
        final partial = File('$basename.part');
        var received = playback != null && details['version'] != 2
            ? await File(playback.mediaUri).length()
            : await partial.exists()
                ? await partial.length()
                : 0;
        int? total = details['total_bytes'] is int
            ? details['total_bytes'] as int
            : null;
        if (details['version'] == 2) {
          received = 0;
          total = 0;
          var known = true;
          for (final track in _tracks(details)) {
            final base = _trackBase(directory, video, track['id']);
            final trackDetails = _details(await _manifest(File('$base.json')));
            final media = File('$base.media');
            final part = File('$base.part');
            received += await _verifiedMedia(base)
                ? await media.length()
                : await part.exists()
                    ? await part.length()
                    : 0;
            final length = trackDetails['total_bytes'];
            if (length is int && length > 0) {
              total = total! + length;
            } else {
              known = false;
            }
          }
          if (!known) total = null;
        }
        result.add(StudyCacheEntry(
            video: video,
            complete: playback != null,
            receivedBytes: received,
            totalBytes: total,
            layout: details['version'] == 2 ? '${details['layout']}' : 'single',
            attachments:
                playback?.attachments ?? await localAttachments(video)));
      } on FormatException {
        continue;
      }
    }
    _checkScope(scope);
    return result;
  }

  Future<List<Video>> list() async => (await entries())
      .where((entry) => entry.complete)
      .map((entry) => entry.video)
      .toList();

  Future<void> remove(Video video) async {
    final scope = _requireScope();
    final key = '$scope:${_fileKey(video)}';
    if (!_removing.add(key)) return;
    try {
      final transfers = [_active[key], _active['$key:attachments']]
          .whereType<_Transfer>()
          .toList();
      for (final transfer in transfers) {
        transfer.token.cancel('Removed');
      }
      for (final transfer in transfers) {
        await transfer.done.future;
      }
      final directory = await _directory(scope);
      final prefix = '${_fileKey(video)}.';
      await for (final file in directory.list()) {
        _checkScope(scope);
        if (file is File && file.uri.pathSegments.last.startsWith(prefix)) {
          await file.delete();
        }
      }
      progress.remove(key);
      errors.remove(key);
      attachmentErrors.remove(key);
    } finally {
      _removing.remove(key);
      revision.value++;
    }
  }

  void dispose() {
    _authWorker?.dispose();
    for (final transfer in _active.values) {
      transfer.token.cancel('Disposed');
    }
    _dio.close(force: true);
  }
}
