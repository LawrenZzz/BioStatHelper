import 'dart:async';
import 'dart:convert';

// The host application should declare crypto ^3.0.7 directly.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum BiliErrorKind {
  input,
  network,
  login,
  permission,
  protection,
  platform,
  storage,
  cancelled
}

class BiliException implements Exception {
  final String message;
  final int? code;
  final BiliErrorKind kind;
  const BiliException(this.message,
      {this.code, this.kind = BiliErrorKind.platform});
  @override
  String toString() => message;
}

enum BiliSearchOrder { relevance, clicks, published, favorites }

enum BiliUploaderOrder { published, clicks, favorites }

enum BiliQrStatus { waiting, scanned, expired, authenticated }

class BiliPage<T> {
  final List<T> items;
  final int page;
  final int? total;
  final bool hasMore;
  BiliPage(Iterable<T> items,
      {required this.page, this.total, required this.hasMore})
      : items = List.unmodifiable(items);
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> _maps(dynamic value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _text(dynamic value) => value?.toString() ?? '';
String _image(dynamic value) {
  final text = _text(value);
  return text.startsWith('//') ? 'https:$text' : text;
}

String _title(dynamic value) => _text(value)
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');
Duration _duration(dynamic value) {
  if (value is String && value.contains(':')) {
    return Duration(
        seconds: value
            .split(':')
            .fold<int>(0, (sum, item) => sum * 60 + _int(item)));
  }
  return Duration(seconds: _int(value));
}

class BiliPart {
  final int cid;
  final int page;
  final String title;
  final Duration duration;
  const BiliPart(
      {required this.cid,
      required this.page,
      required this.title,
      required this.duration});
  factory BiliPart.fromJson(Map<String, dynamic> json) => BiliPart(
      cid: _int(json['cid']),
      page: _int(json['page']),
      title: _title(json['part'] ?? json['title']),
      duration: _duration(json['duration_seconds'] ?? json['duration']));
  Map<String, dynamic> toSourceData() => {
        'cid': cid,
        'page': page,
        'title': title,
        'duration_seconds': duration.inSeconds,
      };
}

class BiliVideo {
  final String bvid;
  final int aid;
  final String title;
  final String cover;
  final String description;
  final int ownerMid;
  final String ownerName;
  final Duration duration;
  final List<BiliPart> parts;
  final DateTime? publishedAt;
  BiliVideo(
      {required this.bvid,
      required this.aid,
      required this.title,
      required this.cover,
      required this.description,
      required this.ownerMid,
      required this.ownerName,
      required this.duration,
      this.publishedAt,
      List<BiliPart> parts = const []})
      : parts = List.unmodifiable(parts);
  factory BiliVideo.fromJson(Map<String, dynamic> json) {
    final owner = _map(json['owner'] ?? json['upper']);
    return BiliVideo(
        bvid: _text(json['bvid'] ?? json['bv_id']),
        aid: _int(json['aid'] ?? json['id']),
        title: _title(json['title']),
        cover: _image(json['pic'] ?? json['cover']),
        description: _text(json['desc'] ?? json['description']),
        ownerMid: _int(owner['mid'] ?? json['mid']),
        ownerName: _text(owner['name'] ?? json['author']),
        duration: _duration(json['duration'] ?? json['length']),
        publishedAt: _int(json['pubdate'] ?? json['created']) > 0
            ? DateTime.fromMillisecondsSinceEpoch(
                _int(json['pubdate'] ?? json['created']) * 1000,
                isUtc: true)
            : null,
        parts: _maps(json['pages']).map(BiliPart.fromJson).toList());
  }
  factory BiliVideo.fromSourceData(Map<String, dynamic> value) {
    final json =
        value['source_data'] is Map ? _map(value['source_data']) : value;
    return BiliVideo(
        bvid: _text(json['bvid']),
        aid: _int(json['aid']),
        title: _text(json['video_title'] ?? json['title']),
        cover: _image(json['cover']),
        description: _text(json['description']),
        ownerMid: _int(json['owner_mid']),
        ownerName: _text(json['owner_name']),
        duration: _duration(
            json['video_duration_seconds'] ?? json['duration_seconds']),
        publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
        parts: _maps(json['parts']).map(BiliPart.fromJson).toList());
  }

  /// Stable metadata only. No cookies, signed CDN URLs, or account identifiers.
  Map<String, dynamic> toSourceData({BiliPart? part, bool compact = false}) => {
        'source': 'bilibili',
        'bvid': bvid,
        'aid': aid,
        'cid': part?.cid,
        'page': part?.page ?? 1,
        'title': part?.title ?? title,
        'video_title': title,
        'cover': cover,
        'description': description,
        'owner_mid': ownerMid,
        'owner_name': ownerName,
        'duration_seconds': (part?.duration ?? duration).inSeconds,
        'video_duration_seconds': duration.inSeconds,
        'part_count': parts.length,
        if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
        'url': 'https://www.bilibili.com/video/$bvid/?p=${part?.page ?? 1}',
        'parts': (compact && part != null ? [part] : parts)
            .map((p) => p.toSourceData())
            .toList(),
      };
}

class BiliAccount {
  final int mid;
  final String name;
  final String avatar;
  final bool vip;
  const BiliAccount(
      {required this.mid,
      required this.name,
      required this.avatar,
      this.vip = false});
}

class BiliUploader {
  final int mid;
  final String name;
  final String avatar;
  final String description;
  const BiliUploader(
      {required this.mid,
      required this.name,
      required this.avatar,
      this.description = ''});
  factory BiliUploader.fromJson(Map<String, dynamic> json) => BiliUploader(
      mid: _int(json['mid']),
      name: _text(json['name'] ?? json['uname']),
      avatar: _image(json['face']),
      description: _text(json['sign']));
}

class BiliCollection {
  final int id;
  final int ownerMid;
  final String title;
  final String cover;
  final int count;
  const BiliCollection(
      {required this.id,
      required this.ownerMid,
      required this.title,
      required this.cover,
      required this.count});
  factory BiliCollection.fromJson(Map<String, dynamic> json,
      {int ownerMid = 0}) {
    final meta = json['meta'] is Map ? _map(json['meta']) : json;
    return BiliCollection(
        id: _int(meta['season_id'] ?? meta['id']),
        ownerMid: _int(meta['mid'] ?? _map(meta['upper'])['mid'] ?? ownerMid),
        title: _title(meta['name'] ?? meta['title']),
        cover: _image(meta['cover']),
        count: _int(meta['total'] ?? meta['media_count']));
  }
}

class BiliFavoriteFolder {
  final int id;
  final String title;
  final int count;
  const BiliFavoriteFolder(
      {required this.id, required this.title, required this.count});
}

class BiliQrLogin {
  final String url;
  final String key;
  const BiliQrLogin({required this.url, required this.key});
  @override
  String toString() => 'BiliQrLogin(redacted)';
}

class BiliPlayback {
  /// MP4 segments in server order; do not silently discard segments after first.
  final List<String> segments;
  final String? videoUrl;
  final String? audioUrl;
  final Map<String, String> headers;
  final int quality;
  final int requestedQuality;
  final List<int> availableQualities;

  /// Apply this to the player; it is not a playurl API parameter.
  final double speed;
  final bool isDash;
  BiliPlayback(
      {required List<String> segments,
      this.videoUrl,
      this.audioUrl,
      required Map<String, String> headers,
      required this.quality,
      required this.requestedQuality,
      required List<int> availableQualities,
      required this.speed,
      required this.isDash})
      : segments = List.unmodifiable(segments),
        headers = Map.unmodifiable(headers),
        availableQualities = List.unmodifiable(availableQualities);
}

class BiliSubtitle {
  final String id;
  final String language;
  final String label;
  final String url;
  const BiliSubtitle(
      {required this.id,
      required this.language,
      required this.label,
      required this.url});
}

class BiliSubtitleCue {
  final double from;
  final double to;
  final String content;
  const BiliSubtitleCue(
      {required this.from, required this.to, required this.content});
}

class BiliInput {
  final String? bvid;
  final int page;
  final Uri? shortLink;
  final String? keyword;
  const BiliInput({this.bvid, this.page = 1, this.shortLink, this.keyword});
}

/// Independently implemented Bilibili web protocol adapter. Never use ApiClient.
/// Own one instance per account screen/controller; initialize before account use.
class BilibiliService extends ChangeNotifier {
  static const _cookieKey = 'bilibili.local.cookies.v1';
  static const _protectionKey = 'bilibili.local.readOnly.v1';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const _cookieNames = {
    'SESSDATA',
    'bili_jct',
    'DedeUserID',
    'DedeUserID__ckMd5',
    'sid'
  };
  static const _linkHosts = {
    'www.bilibili.com',
    'm.bilibili.com',
    'bilibili.com',
    'b23.tv',
    'bili2233.cn'
  };
  static const _qrHosts = {'passport.bilibili.com', 'account.bilibili.com'};
  static const _mixOrder = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52
  ];
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final DateTime Function() _clock;
  Map<String, String> _cookies = {};
  BiliAccount? _account;
  bool _readOnly = true;
  bool _disposed = false;
  int _epoch = 0;
  int _protectionEpoch = 0;
  String? _activeQr;
  String? _imgKey;
  String? _subKey;
  DateTime? _keyTime;
  Future<void> _sessionQueue = Future.value();
  Future<void>? _initializing;

  BilibiliService(
      {HttpClientAdapter? adapter,
      FlutterSecureStorage? storage,
      DateTime Function()? clock})
      : _dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 15),
            followRedirects: false,
            maxRedirects: 0,
            validateStatus: (_) => true)),
        _storage = storage ??
            const FlutterSecureStorage(
                iOptions: IOSOptions(synchronizable: false)),
        _clock = clock ?? DateTime.now {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }
  BiliAccount? get account => _account;
  bool get readOnly => _readOnly;
  bool get isLoggedIn => _account != null;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _sessionQueue.then((_) => action());
    _sessionQueue =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> initialize() {
    final epoch = _epoch;
    final protectionEpoch = _protectionEpoch;
    return _initializing ??= _serialize(() async {
      try {
        final saved = await _storage.read(key: _cookieKey);
        final protection = await _storage.read(key: _protectionKey);
        if (epoch != _epoch || _disposed) return;
        if (saved != null) {
          final parsed = _map(jsonDecode(saved));
          _cookies = {
            for (final e in parsed.entries)
              if (_cookieNames.contains(e.key) &&
                  _safeCookie(e.value.toString()))
                e.key: e.value.toString()
          };
        }
        if (protectionEpoch == _protectionEpoch) {
          _readOnly = protection != 'false';
        }
        _changed();
      } catch (_) {
        _initializing = null;
        throw const BiliException(
            'Cannot read Bilibili credentials from local secure storage.',
            kind: BiliErrorKind.storage);
      }
    });
  }

  Future<void> setReadOnly(bool enabled) async {
    final epoch = ++_protectionEpoch;
    if (enabled) {
      _readOnly = true;
      _changed();
    }
    await _serialize(() async {
      if (epoch != _protectionEpoch || _disposed) return;
      try {
        await _storage.write(key: _protectionKey, value: enabled.toString());
      } catch (_) {
        throw const BiliException(
            'Cannot save account protection in local secure storage.',
            kind: BiliErrorKind.storage);
      }
      if (epoch == _protectionEpoch && !_disposed) {
        _readOnly = enabled;
        _changed();
      }
    });
  }

  Future<BiliAccount?> refreshAccount() async {
    final epoch = _epoch;
    if (_cookies['SESSDATA']?.isNotEmpty != true) return null;
    final root = await _json('/x/web-interface/nav', allowLoggedOut: true);
    if (epoch != _epoch) return _account;
    final data = _map(root['data']);
    _cacheKeys(data);
    _account = root['code'] == 0 && data['isLogin'] == true
        ? _parseAccount(data)
        : null;
    _changed();
    return _account;
  }

  /// This is deliberately separate from learning-data exports: it is a secret.
  Future<String> exportLogin() async {
    await initialize();
    if (_cookies['SESSDATA']?.isNotEmpty != true) {
      throw const BiliException('没有可导出的 B站登录信息。');
    }
    return jsonEncode({
      'format': 'biostat-bilibili-login',
      'version': 1,
      'cookies': _cookies,
    });
  }

  Future<void> importLogin(String input) async {
    await initialize();
    if (input.length > 65536) {
      throw const BiliException('登录文件过大。', kind: BiliErrorKind.input);
    }
    final fresh = <String, String>{};
    void add(Object? key, Object? value) {
      if (key is String &&
          value is String &&
          _cookieNames.contains(key) &&
          _safeCookie(value)) {
        fresh[key] = value;
      }
    }

    try {
      final data = jsonDecode(input);
      final candidate =
          data is Map ? data['cookies'] ?? data['cookie'] ?? data : data;
      if (candidate is Map) {
        candidate.forEach(add);
      } else if (candidate is List) {
        for (final entry in candidate.whereType<Map>()) {
          final domain = '${entry['domain'] ?? '.bilibili.com'}';
          if (domain == '.bilibili.com' ||
              domain == 'bilibili.com' ||
              domain == 'www.bilibili.com') {
            add(entry['name'], entry['value']);
          }
        }
      } else if (candidate is String) {
        _parseCookieHeader(candidate, add);
      }
    } on FormatException {
      _parseCookieHeader(input, add);
    }
    if (fresh['SESSDATA']?.isNotEmpty != true) {
      throw const BiliException('文件中没有有效的 B站 Cookie。',
          kind: BiliErrorKind.input);
    }
    final epoch = ++_epoch;
    _activeQr = null;
    final nav = await _json('/x/web-interface/nav', cookieOverride: fresh);
    final verified = _map(nav['data']);
    if (verified['isLogin'] != true || _int(verified['mid']) <= 0) {
      throw const BiliException('导入的登录信息已失效，原账号保持不变。',
          kind: BiliErrorKind.login);
    }
    await _serialize(() async {
      if (epoch != _epoch || _disposed) _cancelled();
      try {
        await _storage.write(key: _protectionKey, value: 'true');
        await _storage.write(key: _cookieKey, value: jsonEncode(fresh));
      } catch (_) {
        throw const BiliException('无法保存到本机安全存储。', kind: BiliErrorKind.storage);
      }
      if (epoch != _epoch || _disposed) _cancelled();
      _cookies = fresh;
      _account = _parseAccount(verified);
      _readOnly = true;
      _protectionEpoch++;
      _cacheKeys(verified);
      _changed();
    });
  }

  static void _parseCookieHeader(
      String value, void Function(Object?, Object?) add) {
    for (final part in value.trim().split(';')) {
      final at = part.indexOf('=');
      if (at > 0) {
        add(part.substring(0, at).trim(), part.substring(at + 1).trim());
      }
    }
  }

  BiliAccount _parseAccount(Map<String, dynamic> data) => BiliAccount(
      mid: _int(data['mid']),
      name: _text(data['uname']),
      avatar: _image(data['face']),
      vip: _int(_map(data['vip'])['status'] ?? data['vipStatus']) == 1);

  /// Logout is local, including protection reset; it does not revoke other devices.
  Future<void> logout() {
    _epoch++;
    _protectionEpoch++;
    _activeQr = null;
    _cookies = {};
    _account = null;
    _readOnly = true;
    _changed();
    return _serialize(() async {
      try {
        await _storage.delete(key: _cookieKey);
        await _storage.delete(key: _protectionKey);
      } catch (_) {
        throw const BiliException(
            'Local logout could not erase secure storage. Retry before closing the app.',
            kind: BiliErrorKind.storage);
      }
    });
  }

  Future<BiliQrLogin> createQrLogin() async {
    final epoch = ++_epoch;
    _activeQr = null;
    final root = await _json('/x/passport-login/web/qrcode/generate',
        passport: true, authenticated: false);
    if (_disposed || epoch != _epoch) _cancelled();
    final data = _map(root['data']);
    final rawUrl = data['url'];
    final key = data['qrcode_key'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (url == null ||
        !_safeUri(url) ||
        !_qrHosts.contains(url.host) ||
        key is! String ||
        key.trim().isEmpty) {
      throw const BiliException('B站返回的登录二维码无效，请刷新二维码后重试。');
    }
    _activeQr = key;
    return BiliQrLogin(url: url.toString(), key: _activeQr!);
  }

  void cancelQrLogin() {
    _epoch++;
    _activeQr = null;
  }

  Never _cancelled() =>
      throw const BiliException('Login request was cancelled.',
          kind: BiliErrorKind.cancelled);

  Future<BiliQrStatus> pollQrLogin(BiliQrLogin login) async {
    final epoch = _epoch;
    if (login.key != _activeQr || _disposed) _cancelled();
    final response = await _send(
        Uri.https('passport.bilibili.com', '/x/passport-login/web/qrcode/poll',
            {'qrcode_key': login.key}),
        authenticated: false);
    final root = _decode(response.data);
    _check(root);
    if (epoch != _epoch || _disposed) _cancelled();
    final data = _map(root['data']);
    switch (_int(data['code'])) {
      case 86101:
        return BiliQrStatus.waiting;
      case 86090:
        return BiliQrStatus.scanned;
      case 86038:
        _activeQr = null;
        return BiliQrStatus.expired;
      case 0:
        break;
      default:
        throw BiliException('Bilibili could not confirm this QR login.',
            code: _int(data['code']));
    }
    final fresh = <String, String>{};
    for (final header in response.headers['set-cookie'] ?? const <String>[]) {
      // Some gateways fold multiple Set-Cookie fields; do not split Expires dates.
      for (final cookie in header.split(RegExp(r',(?=\s*[A-Za-z0-9_]+\s*=)'))) {
        final first = cookie.split(';').first;
        final at = first.indexOf('=');
        if (at > 0) {
          final name = first.substring(0, at).trim();
          final value = first.substring(at + 1).trim();
          if (_cookieNames.contains(name) && _safeCookie(value)) {
            fresh[name] = value;
          }
        }
      }
    }
    if (fresh['SESSDATA']?.isNotEmpty != true ||
        fresh['bili_jct']?.isNotEmpty != true) {
      throw const BiliException('B站未返回完整登录凭据，请刷新二维码并重新扫码确认。',
          kind: BiliErrorKind.login);
    }
    final nav = await _json('/x/web-interface/nav', cookieOverride: fresh);
    final verified = _map(nav['data']);
    if (verified['isLogin'] != true || _int(verified['mid']) <= 0) {
      throw const BiliException('B站未验证此登录状态，请重新扫码确认。',
          kind: BiliErrorKind.login);
    }
    await _serialize(() async {
      if (epoch != _epoch || _disposed || login.key != _activeQr) _cancelled();
      try {
        await _storage.delete(key: _protectionKey);
        await _storage.write(key: _cookieKey, value: jsonEncode(fresh));
      } catch (_) {
        throw const BiliException('无法将B站登录状态保存到设备安全存储，请检查设备权限。',
            kind: BiliErrorKind.storage);
      }
      if (epoch != _epoch || _disposed) {
        await _storage.delete(key: _cookieKey);
        _cancelled();
      }
      _cookies = fresh;
      _account = _parseAccount(verified);
      _cacheKeys(verified);
      _activeQr = null;
      _protectionEpoch++;
      _readOnly = true;
      _changed();
    });
    return BiliQrStatus.authenticated;
  }

  /// Pure parser: external URLs are rejected, never treated as search keywords.
  static BiliInput parseInput(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw const BiliException('Enter a keyword, BV ID or Bilibili link.',
          kind: BiliErrorKind.input);
    }
    if (RegExp(r'^BV[0-9A-Za-z]{10}$', caseSensitive: false).hasMatch(text)) {
      return BiliInput(bvid: 'BV${text.substring(2)}');
    }
    var candidate =
        RegExp(r'https?://[^\s<>"\u300b\u3002]+', caseSensitive: false)
            .firstMatch(text)
            ?.group(0);
    candidate ??= RegExp(
                r'^(?:www\.|m\.)?bilibili\.com/|^b23\.tv/|^bili2233\.cn/',
                caseSensitive: false)
            .hasMatch(text)
        ? 'https://$text'
        : null;
    if (candidate != null) {
      final uri = Uri.tryParse(candidate);
      if (uri == null ||
          !_linkHosts.contains(uri.host.toLowerCase()) ||
          uri.userInfo.isNotEmpty ||
          (uri.hasPort && uri.port != 443 && uri.port != 80)) {
        throw const BiliException(
            'Only official Bilibili video links and b23 short links are accepted.',
            kind: BiliErrorKind.input);
      }
      final secure = uri.replace(scheme: 'https', port: 443);
      if (uri.host == 'b23.tv' || uri.host == 'bili2233.cn') {
        return BiliInput(shortLink: secure);
      }
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length < 2 ||
          segments[0] != 'video' ||
          !RegExp(r'^BV[0-9A-Za-z]{10}$', caseSensitive: false)
              .hasMatch(segments[1])) {
        throw const BiliException('This is not a supported BV video URL.',
            kind: BiliErrorKind.input);
      }
      final page = uri.queryParameters.containsKey('p')
          ? int.tryParse(uri.queryParameters['p']!)
          : 1;
      if (page == null || page <= 0) {
        throw const BiliException('Invalid video part number.',
            kind: BiliErrorKind.input);
      }
      return BiliInput(bvid: 'BV${segments[1].substring(2)}', page: page);
    }
    if (text.contains('://') || text.startsWith('//')) {
      throw const BiliException('Unsupported URL.', kind: BiliErrorKind.input);
    }
    return BiliInput(keyword: text);
  }

  Future<BiliInput> resolveInput(String input) async {
    var target = parseInput(input);
    var uri = target.shortLink;
    if (uri == null) return target;
    for (var i = 0; i < 5; i++) {
      if (!_safeUri(uri!) || !_linkHosts.contains(uri.host)) {
        throw const BiliException('Blocked an unsafe short-link redirect.',
            kind: BiliErrorKind.input);
      }
      final response = await _send(uri, authenticated: false, shortLink: true);
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        throw const BiliException(
            'The short link did not redirect to a BV video.');
      }
      final location = response.headers.value('location');
      if (location == null) {
        throw const BiliException(
            'The short-link redirect has no destination.');
      }
      uri = uri.resolve(location);
      if (!_safeUri(uri) || !_linkHosts.contains(uri.host)) {
        throw const BiliException('Blocked an unsafe short-link redirect.',
            kind: BiliErrorKind.input);
      }
      target = parseInput(uri.toString());
      if (target.bvid != null) return target;
      uri = target.shortLink;
    }
    throw const BiliException('Too many short-link redirects.');
  }

  /// Deterministic WBI protocol signing; timestamp is Unix seconds.
  static Map<String, String> signWbi(Map<String, dynamic> parameters,
      {required String imgKey,
      required String subKey,
      required int timestamp}) {
    final material = '$imgKey$subKey';
    if (material.length != 64 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(material)) {
      throw const BiliException('Invalid WBI signing keys.');
    }
    final mixin = _mixOrder.take(32).map((i) => material[i]).join();
    final values = <String, String>{
      for (final e in parameters.entries)
        if (e.key != 'w_rid' && e.key != 'wts' && e.value != null)
          e.key: e.value.toString().replaceAll(RegExp("[!'()*]"), ''),
      'wts': timestamp.toString(),
    };
    final keys = values.keys.toList()..sort();
    final query = keys
        .map((k) =>
            '${Uri.encodeComponent(k)}=${Uri.encodeComponent(values[k]!)}')
        .join('&');
    return {
      ...values,
      'w_rid': md5.convert(utf8.encode('$query$mixin')).toString()
    };
  }

  void _cacheKeys(Map<String, dynamic> nav) {
    final image = _map(nav['wbi_img']);
    String key(dynamic value) =>
        Uri.tryParse(_text(value))?.pathSegments.lastOrNull?.split('.').first ??
        '';
    final img = key(image['img_url']);
    final sub = key(image['sub_url']);
    if (img.length == 32 && sub.length == 32) {
      _imgKey = img;
      _subKey = sub;
      _keyTime = _clock();
    }
  }

  Future<Map<String, String>> _signed(Map<String, dynamic> parameters) async {
    if (_imgKey == null ||
        _keyTime == null ||
        _clock().difference(_keyTime!) > const Duration(hours: 1)) {
      final nav = await _json('/x/web-interface/nav', allowLoggedOut: true);
      _cacheKeys(_map(nav['data']));
    }
    if (_imgKey == null || _subKey == null) {
      throw const BiliException(
          'Bilibili did not provide WBI signing keys. Retry later.');
    }
    return signWbi(parameters,
        imgKey: _imgKey!,
        subKey: _subKey!,
        timestamp: _clock().millisecondsSinceEpoch ~/ 1000);
  }

  Future<BiliPage<BiliVideo>> search(String input,
      {int page = 1, BiliSearchOrder order = BiliSearchOrder.relevance}) async {
    _positive(page, 'Page');
    final target = await resolveInput(input);
    if (target.bvid != null) {
      if (page > 1) return BiliPage([], page: page, total: 1, hasMore: false);
      return BiliPage([await getVideo(target.bvid!)],
          page: 1, total: 1, hasMore: false);
    }
    final params = await _signed({
      'search_type': 'video',
      'keyword': target.keyword,
      'page': page,
      'page_size': 20,
      'order': const ['totalrank', 'click', 'pubdate', 'stow'][order.index]
    });
    final data = _map((await _json('/x/web-interface/wbi/search/type',
        parameters: params))['data']);
    final items = _maps(data['result'])
        .map(BiliVideo.fromJson)
        .where((v) => v.bvid.isNotEmpty)
        .toList();
    final total = _int(data['numResults']);
    return BiliPage(items,
        page: page, total: total, hasMore: page < _int(data['numPages']));
  }

  Future<BiliVideo> getVideo(String bvid) async {
    _bvid(bvid);
    final data = _map((await _json('/x/web-interface/view',
        parameters: {'bvid': bvid}))['data']);
    final video = BiliVideo.fromJson(data);
    if (video.bvid.isEmpty || video.parts.isEmpty) {
      throw const BiliException(
          'Video details contain no playable parts. The video may be unavailable.');
    }
    return video;
  }

  Future<BiliUploader> getUploader(int mid) async {
    _positive(mid, 'Uploader ID');
    final parameters = await _signed({'mid': mid});
    return BiliUploader.fromJson(_map((await _json('/x/space/wbi/acc/info',
        parameters: parameters))['data']));
  }

  Future<BiliPage<BiliVideo>> getUploaderVideos(int mid,
      {int page = 1,
      BiliUploaderOrder order = BiliUploaderOrder.published}) async {
    _positive(mid, 'Uploader ID');
    _positive(page, 'Page');
    final parameters = await _signed({
      'mid': mid,
      'pn': page,
      'ps': 20,
      'order': const ['pubdate', 'click', 'stow'][order.index]
    });
    final data = _map((await _json('/x/space/wbi/arc/search',
        parameters: parameters))['data']);
    final items =
        _maps(_map(data['list'])['vlist']).map(BiliVideo.fromJson).toList();
    final total = _int(_map(data['page'])['count']);
    return BiliPage(items,
        page: page, total: total, hasMore: page * 20 < total);
  }

  Future<BiliPage<BiliCollection>> getCollections(int mid,
      {int page = 1}) async {
    _positive(mid, 'Uploader ID');
    _positive(page, 'Page');
    final data = _map((await _json('/x/polymer/web-space/seasons_series_list',
        parameters: {'mid': mid, 'page_num': page, 'page_size': 20}))['data']);
    final raw = _maps(_map(data['items_lists'])['seasons_list']);
    return BiliPage(raw.map((e) => BiliCollection.fromJson(e, ownerMid: mid)),
        page: page, hasMore: raw.length == 20);
  }

  Future<BiliPage<BiliVideo>> getCollectionVideos(int mid, int collectionId,
      {int page = 1, bool reverse = false}) async {
    _positive(mid, 'Uploader ID');
    _positive(collectionId, 'Collection ID');
    _positive(page, 'Page');
    final data = _map(
        (await _json('/x/polymer/web-space/seasons_archives_list', parameters: {
      'mid': mid,
      'season_id': collectionId,
      'page_num': page,
      'page_size': 20,
      'sort_reverse': reverse.toString()
    }))['data']);
    final items = _maps(data['archives']).map(BiliVideo.fromJson).toList();
    final total =
        _int(_map(data['meta'])['total'] ?? _map(data['page'])['total']);
    return BiliPage(items,
        page: page,
        total: total > 0 ? total : null,
        hasMore: total > 0 ? page * 20 < total : items.length == 20);
  }

  int _requireAccount() {
    if (_account == null || _cookies['SESSDATA']?.isNotEmpty != true) {
      throw const BiliException(
          'Sign in to Bilibili first. The session may have expired.',
          kind: BiliErrorKind.login);
    }
    return _account!.mid;
  }

  Future<List<BiliFavoriteFolder>> getFavoriteFolders() async {
    final mid = _requireAccount();
    final data = _map((await _json('/x/v3/fav/folder/created/list-all',
        parameters: {'up_mid': mid}))['data']);
    return _maps(data['list'])
        .map((e) => BiliFavoriteFolder(
            id: _int(e['id']),
            title: _title(e['title']),
            count: _int(e['media_count'])))
        .toList();
  }

  Future<BiliPage<BiliVideo>> getFavoriteVideos(int folderId,
      {int page = 1, String order = 'mtime'}) async {
    _requireAccount();
    _positive(folderId, 'Folder ID');
    _positive(page, 'Page');
    if (!['mtime', 'view', 'pubtime'].contains(order)) {
      throw const BiliException('Unsupported favorites sort.',
          kind: BiliErrorKind.input);
    }
    final data = _map((await _json('/x/v3/fav/resource/list', parameters: {
      'media_id': folderId,
      'pn': page,
      'ps': 20,
      'order': order,
      'type': 0,
      'tid': 0,
      'platform': 'web'
    }))['data']);
    return BiliPage(
        _maps(data['medias'])
            .where((e) => e['type'] == null || _int(e['type']) == 2)
            .map(BiliVideo.fromJson),
        page: page,
        total: _int(_map(data['info'])['media_count']),
        hasMore: data['has_more'] == true);
  }

  Future<BiliPage<BiliUploader>> getFollowings({int page = 1}) async {
    final mid = _requireAccount();
    _positive(page, 'Page');
    final data = _map((await _json('/x/relation/followings', parameters: {
      'vmid': mid,
      'pn': page,
      'ps': 20,
      'order': 'desc'
    }))['data']);
    final total = _int(data['total']);
    return BiliPage(_maps(data['list']).map(BiliUploader.fromJson),
        page: page, total: total, hasMore: page * 20 < total);
  }

  Future<BiliPage<BiliCollection>> getSubscribedCollections(
      {int page = 1}) async {
    final mid = _requireAccount();
    _positive(page, 'Page');
    final data = _map((await _json('/x/v3/fav/folder/collected/list',
        parameters: {
          'up_mid': mid,
          'pn': page,
          'ps': 20,
          'platform': 'web'
        }))['data']);
    final raw = _maps(data['list']);
    // type 21 is a UGC season; ordinary followed favorite folders are not seasons.
    final items =
        raw.where((e) => _int(e['type']) == 21).map(BiliCollection.fromJson);
    final total = _int(data['count']);
    return BiliPage(items,
        page: page, total: total, hasMore: page * 20 < total);
  }

  Future<void> setLiked(int aid, bool liked) async {
    _positive(aid, 'Video ID');
    await _write(
        '/x/web-interface/archive/like', {'aid': aid, 'like': liked ? 1 : 2});
  }

  Future<void> addCoins(int aid, {int count = 1}) async {
    _positive(aid, 'Video ID');
    if (count != 1 && count != 2) {
      throw const BiliException('Coin count must be 1 or 2.',
          kind: BiliErrorKind.input);
    }
    await _write('/x/web-interface/coin/add',
        {'aid': aid, 'multiply': count, 'select_like': 0});
  }

  Future<void> updateFavorite(int aid,
      {List<int> addFolderIds = const [],
      List<int> removeFolderIds = const []}) async {
    _positive(aid, 'Video ID');
    if (addFolderIds.isEmpty && removeFolderIds.isEmpty) {
      throw const BiliException('Select a favorite folder.',
          kind: BiliErrorKind.input);
    }
    for (final id in [...addFolderIds, ...removeFolderIds]) {
      _positive(id, 'Folder ID');
    }
    if (addFolderIds.any(removeFolderIds.contains)) {
      throw const BiliException(
          'A folder cannot be added and removed together.',
          kind: BiliErrorKind.input);
    }
    await _write('/x/v3/fav/resource/deal', {
      'rid': aid,
      'type': 2,
      'add_media_ids': addFolderIds.join(','),
      'del_media_ids': removeFolderIds.join(',')
    });
  }

  Future<void> setFollowing(int mid, bool following) async {
    _positive(mid, 'Uploader ID');
    await _write('/x/relation/modify',
        {'fid': mid, 'act': following ? 1 : 2, 're_src': 11});
  }

  Future<void> _write(String path, Map<String, dynamic> data) async {
    if (_readOnly) {
      throw const BiliException(
          'Account read-only protection is enabled. Disable it explicitly before an account write.',
          kind: BiliErrorKind.protection);
    }
    _requireAccount();
    final csrf = _cookies['bili_jct'];
    if (csrf == null || csrf.isEmpty) {
      throw const BiliException('The login has no CSRF token. Sign in again.',
          kind: BiliErrorKind.login);
    }
    // No automatic retries: a timeout must not spend coins or repeat a command.
    await _json(path,
        method: 'POST', body: {...data, 'csrf': csrf, 'csrf_token': csrf});
  }

  Future<BiliPlayback> resolvePlayback(String bvid, int cid,
      {int quality = 80, double speed = 1.0}) async {
    _bvid(bvid);
    _positive(cid, 'Part ID');
    _positive(quality, 'Quality');
    if (!speed.isFinite || speed < 0.25 || speed > 4) {
      throw const BiliException('Playback speed must be between 0.25 and 4.',
          kind: BiliErrorKind.input);
    }
    Future<Map<String, dynamic>> load(int fnval) async {
      final parameters = await _signed({
        'bvid': bvid,
        'cid': cid,
        'qn': quality,
        'fnval': fnval,
        'fnver': 0,
        'fourk': 1
      });
      return _map((await _json('/x/player/wbi/playurl',
          parameters: parameters))['data']);
    }

    var data = await load(0);
    if (_int(data['is_preview']) == 1) {
      throw const BiliException(
          'Only a preview is authorized. This content requires membership or purchase; access controls are not bypassed.',
          kind: BiliErrorKind.permission);
    }
    bool notMp4(Map<String, dynamic> value) =>
        _text(value['format']).isNotEmpty &&
        !_text(value['format']).toLowerCase().contains('mp4');
    if ((_maps(data['durl']).isEmpty && _map(data['dash']).isEmpty) ||
        (_maps(data['durl']).isNotEmpty && notMp4(data))) {
      data = await load(16);
    }
    if (_int(data['is_preview']) == 1) {
      throw const BiliException('Only a paid-content preview is authorized.',
          kind: BiliErrorKind.permission);
    }
    final segments = notMp4(data)
        ? <String>[]
        : _maps(data['durl']).map((e) => _mediaUrl(e['url'])).toList();
    final dash = _map(data['dash']);
    final videos = _maps(dash['video'])
      ..sort((a, b) => _int(b['id']).compareTo(_int(a['id'])));
    final audio = _maps(dash['audio'])
      ..sort((a, b) => _int(b['bandwidth']).compareTo(_int(a['bandwidth'])));
    Map<String, dynamic>? selected;
    for (final video in videos) {
      if (_int(video['id']) <= quality) {
        selected = video;
        break;
      }
    }
    selected ??= videos.isEmpty ? null : videos.last;
    final isDash = segments.isEmpty;
    if (isDash && (selected == null || audio.isEmpty)) {
      throw const BiliException(
          'No authorized complete audio/video stream is available. Login, membership, regional or content restrictions may apply.',
          kind: BiliErrorKind.permission);
    }
    return BiliPlayback(
        segments: segments,
        videoUrl: isDash
            ? _mediaUrl(selected!['baseUrl'] ?? selected['base_url'])
            : null,
        audioUrl: isDash
            ? _mediaUrl(audio.first['baseUrl'] ?? audio.first['base_url'])
            : null,
        headers: {
          'Referer': 'https://www.bilibili.com/video/$bvid/',
          'User-Agent': _ua
        },
        quality: isDash ? _int(selected!['id']) : _int(data['quality']),
        requestedQuality: quality,
        availableQualities: (data['accept_quality'] is List
                ? data['accept_quality'] as List
                : const [])
            .map(_int)
            .toList(),
        speed: speed,
        isDash: isDash);
  }

  Future<List<BiliSubtitle>> getSubtitles(String bvid, int cid) async {
    _bvid(bvid);
    _positive(cid, 'Part ID');
    final parameters = await _signed({'bvid': bvid, 'cid': cid});
    final data =
        _map((await _json('/x/player/wbi/v2', parameters: parameters))['data']);
    if (data['need_login_subtitle'] == true) {
      throw const BiliException('Sign in to access subtitles for this video.',
          kind: BiliErrorKind.login);
    }
    return _maps(_map(data['subtitle'])['subtitles']).map((e) {
      final url = _image(e['subtitle_url']);
      final uri = Uri.tryParse(url);
      if (uri == null) {
        throw const BiliException('Invalid subtitle URL.',
            kind: BiliErrorKind.input);
      }
      _validateSubtitle(uri);
      return BiliSubtitle(
          id: _text(e['id_str'] ?? e['id']),
          language: _text(e['lan']),
          label: _text(e['lan_doc']),
          url: url);
    }).toList();
  }

  Future<List<BiliSubtitleCue>> getSubtitleBody(BiliSubtitle subtitle) async {
    final uri = Uri.tryParse(_image(subtitle.url));
    if (uri == null) {
      throw const BiliException('Invalid subtitle URL.',
          kind: BiliErrorKind.input);
    }
    _validateSubtitle(uri);
    final response = await _send(uri, authenticated: false, subtitle: true);
    final body = _decode(response.data);
    if (body['body'] is! List) {
      throw const BiliException('Bilibili returned invalid subtitle content.');
    }
    return _maps(body['body']).map((e) {
      final from = double.tryParse('${e['from']}');
      final to = double.tryParse('${e['to']}');
      if (from == null ||
          to == null ||
          !from.isFinite ||
          !to.isFinite ||
          from < 0 ||
          to < from) {
        throw const BiliException('Invalid subtitle cue timing.');
      }
      return BiliSubtitleCue(from: from, to: to, content: _text(e['content']));
    }).toList();
  }

  Future<String> getDanmakuXml(int cid) async {
    _positive(cid, 'Part ID');
    final response = await _send(Uri.https('comment.bilibili.com', '/$cid.xml'),
        authenticated: false, danmaku: true);
    final xml = _text(response.data);
    if (!RegExp(r'<i(?:\s[^>]*)?>').hasMatch(xml) || !xml.contains('</i>')) {
      throw const BiliException('Bilibili did not return danmaku XML.');
    }
    return xml;
  }

  static void _positive(int value, String name) {
    if (value <= 0) {
      throw BiliException('$name must be positive.', kind: BiliErrorKind.input);
    }
  }

  static void _bvid(String value) {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(value)) {
      throw const BiliException('Invalid BV ID.', kind: BiliErrorKind.input);
    }
  }

  static bool _safeUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443);
  static bool _safeCookie(String value) =>
      value.isNotEmpty && !RegExp(r'[\x00-\x20\x7f;,]').hasMatch(value);
  static bool _domain(String host, String domain) =>
      host == domain || host.endsWith('.$domain');
  static void _validateSubtitle(Uri uri) {
    if (!_safeUri(uri) ||
        !(_domain(uri.host, 'hdslb.com') ||
            uri.host == 'subtitle.bilibili.com')) {
      throw const BiliException('Blocked an untrusted subtitle URL.',
          kind: BiliErrorKind.input);
    }
  }

  static String _mediaUrl(dynamic value) {
    var uri = Uri.tryParse(_image(value));
    // Some playurl responses still advertise HTTP CDN URLs. Never play over HTTP.
    if (uri != null &&
        uri.scheme == 'http' &&
        (!uri.hasPort || uri.port == 80)) {
      uri = uri.replace(scheme: 'https', port: 443);
    }
    final host = uri?.host ?? '';
    if (uri == null ||
        !_safeUri(uri) ||
        !['bilivideo.com', 'bilivideo.cn', 'bilivideo.net']
            .any((d) => _domain(host, d))) {
      throw const BiliException('Bilibili returned an untrusted media URL.',
          kind: BiliErrorKind.input);
    }
    return uri.toString();
  }

  Future<Map<String, dynamic>> _json(String path,
      {Map<String, dynamic> parameters = const {},
      bool passport = false,
      bool authenticated = true,
      bool allowLoggedOut = false,
      String method = 'GET',
      Map<String, dynamic>? body,
      Map<String, String>? cookieOverride}) async {
    final uri = Uri.https(
        passport ? 'passport.bilibili.com' : 'api.bilibili.com',
        path,
        parameters.isEmpty
            ? null
            : {for (final e in parameters.entries) e.key: e.value.toString()});
    final response = await _send(uri,
        method: method,
        body: body,
        authenticated: authenticated,
        cookieOverride: cookieOverride);
    final root = _decode(response.data);
    _check(root, allowLoggedOut: allowLoggedOut);
    return root;
  }

  Map<String, dynamic> _decode(dynamic value) {
    try {
      final json = value is String ? jsonDecode(value) : value;
      if (json is! Map) throw const FormatException();
      return _map(json);
    } catch (_) {
      throw const BiliException(
          'Bilibili returned invalid JSON. The platform or a network gateway may be unavailable.');
    }
  }

  void _check(Map<String, dynamic> root, {bool allowLoggedOut = false}) {
    if (!root.containsKey('code')) {
      throw const BiliException('Bilibili response has no status code.');
    }
    final code = int.tryParse('${root['code']}');
    if (code == null) {
      throw const BiliException('Bilibili returned an invalid status code.');
    }
    if (code == 0 || (allowLoggedOut && code == -101)) return;
    if (code == -101 || code == -111) {
      throw BiliException(
          'Bilibili login has expired or is invalid. Sign in again.',
          code: code,
          kind: BiliErrorKind.login);
    }
    if ([-403, -10403, 10015002, 6002105].contains(code)) {
      throw BiliException(
          'Bilibili denied access. Membership, purchase, privacy or regional permission is required; access controls are not bypassed.',
          code: code,
          kind: BiliErrorKind.permission);
    }
    if ([-352, -412, -509].contains(code)) {
      throw BiliException(
          'Bilibili risk control or rate limiting blocked the request. Retry later or verify the account on the official site.',
          code: code);
    }
    if (code == -404 || code == 62002 || code == 62004) {
      throw BiliException('This video is unavailable, removed or private.',
          code: code, kind: BiliErrorKind.permission);
    }
    // Server messages can echo sensitive request data. Never expose them verbatim.
    throw BiliException('Bilibili rejected the request (code $code).',
        code: code);
  }

  Future<Response<dynamic>> _send(Uri uri,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool authenticated = true,
      bool shortLink = false,
      bool subtitle = false,
      bool danmaku = false,
      Map<String, String>? cookieOverride}) async {
    if (_disposed) {
      throw const BiliException('Bilibili service is closed.',
          kind: BiliErrorKind.cancelled);
    }
    var allowed = _safeUri(uri);
    if (shortLink) {
      allowed = allowed && _linkHosts.contains(uri.host);
    } else if (subtitle) {
      _validateSubtitle(uri);
    } else if (danmaku) {
      allowed = allowed &&
          uri.host == 'comment.bilibili.com' &&
          RegExp(r'^/\d+\.xml$').hasMatch(uri.path);
    } else {
      allowed = allowed &&
          ((uri.host == 'api.bilibili.com' && uri.path.startsWith('/x/')) ||
              (uri.host == 'passport.bilibili.com' &&
                  const [
                    '/x/passport-login/web/qrcode/generate',
                    '/x/passport-login/web/qrcode/poll'
                  ].contains(uri.path)));
    }
    if (!allowed) {
      throw const BiliException(
          'Blocked a request outside the Bilibili domain allowlist.',
          kind: BiliErrorKind.input);
    }
    final headers = <String, String>{
      'User-Agent': _ua,
      'Referer': 'https://www.bilibili.com/',
      'Accept': danmaku ? 'application/xml,text/xml' : 'application/json'
    };
    if (uri.path.contains('/search/')) {
      headers['Referer'] = 'https://search.bilibili.com/';
    }
    if (authenticated &&
        uri.host == 'api.bilibili.com' &&
        !shortLink &&
        !subtitle &&
        !danmaku) {
      final cookies = cookieOverride ?? _cookies;
      if (cookies.isNotEmpty) {
        headers['Cookie'] =
            cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }
    }
    try {
      final response = await _dio.requestUri<dynamic>(uri,
          data: body,
          options: Options(
              method: method,
              headers: headers,
              responseType: ResponseType.plain,
              contentType:
                  body == null ? null : Headers.formUrlEncodedContentType,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true));
      final status = response.statusCode ?? 0;
      if (shortLink && [301, 302, 303, 307, 308].contains(status)) {
        return response;
      }
      if (status >= 300 && status < 400) {
        throw const BiliException(
            'Bilibili unexpectedly redirected this request. Redirect was blocked.');
      }
      if (status == 401) {
        throw const BiliException('Bilibili requires login (HTTP 401).',
            kind: BiliErrorKind.login);
      }
      if (status == 403) {
        throw const BiliException(
            'Bilibili denied access (HTTP 403). Check account/content permission or platform risk control.',
            kind: BiliErrorKind.permission);
      }
      if (status == 412 || status == 429) {
        throw BiliException(
            'Bilibili rate limiting or risk control blocked this request (HTTP $status). Retry later.',
            kind: BiliErrorKind.network);
      }
      if (status < 200 || status >= 300) {
        throw BiliException('Bilibili request failed (HTTP $status).',
            kind: BiliErrorKind.network);
      }
      return response;
    } on DioException catch (error) {
      final message = switch (error.type) {
        DioExceptionType.connectionTimeout =>
          'Connection to Bilibili timed out.',
        DioExceptionType.sendTimeout =>
          'Sending the Bilibili request timed out. A submitted account command may already have succeeded; check before retrying.',
        DioExceptionType.receiveTimeout =>
          'Bilibili response timed out. A submitted account command may already have succeeded; check before retrying.',
        DioExceptionType.badCertificate =>
          'Bilibili TLS certificate validation failed. The connection was not trusted.',
        DioExceptionType.cancel => 'Bilibili request was cancelled.',
        DioExceptionType.connectionError =>
          'Cannot connect to Bilibili. Check DNS, network access and proxy settings.',
        _ =>
          'Bilibili network transport failed. Check your connection and retry.',
      };
      throw BiliException(message,
          kind: error.type == DioExceptionType.cancel
              ? BiliErrorKind.cancelled
              : BiliErrorKind.network);
    } catch (error) {
      if (error is BiliException) rethrow;
      throw const BiliException('Bilibili network transport failed.',
          kind: BiliErrorKind.network);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _activeQr = null;
    _cookies = {};
    _account = null;
    _dio.close(force: true);
    super.dispose();
  }
}
