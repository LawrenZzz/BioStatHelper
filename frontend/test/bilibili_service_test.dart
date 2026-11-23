import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bio_stat_helper/app/modules/video/views/bilibili_account_view.dart';
import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _bv = 'BV1xx411c7mD';
const _img = '7cd084941338484aae1ad9425b84077c';
const _sub = '4932caff0ff746eab6f01bf08b70ac45';
const _cookieKey = 'bilibili.local.cookies.v1';
const _protectionKey = 'bilibili.local.readOnly.v1';

Map<String, dynamic> _nav({bool loggedIn = false}) => {
      'code': loggedIn ? 0 : -101,
      'data': {
        'isLogin': loggedIn,
        'mid': 42,
        'uname': 'Test account',
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/$_img.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/$_sub.png'
        },
      },
    };
Map<String, dynamic> _video() => {
      'bvid': _bv,
      'aid': 123,
      'title': '<em class="keyword">Test</em> &amp; video',
      'pic': '',
      'desc': 'Description',
      'duration': 90,
      'owner': {'mid': 42, 'name': 'Teacher'},
      'pages': [
        {'cid': 1001, 'page': 1, 'part': 'Introduction', 'duration': 30},
        {'cid': 1002, 'page': 2, 'part': 'Examples', 'duration': 60},
      ],
    };
ResponseBody _json(Object value,
        {int status = 200, Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...?headers
    });
ResponseBody _data(Object value) => _json({'code': 0, 'data': value});
TypeMatcher<BiliException> _kind(BiliErrorKind kind) =>
    isA<BiliException>().having((e) => e.kind, 'kind', kind);

class _Adapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  _Adapter(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return await handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Input parsing', () {
    test('keyword, BV, shared video URL and part', () {
      expect(BilibiliService.parseInput(' linear models ').keyword,
          'linear models');
      expect(BilibiliService.parseInput(_bv).bvid, _bv);
      final input = BilibiliService.parseInput(
          'Shared https://www.bilibili.com/video/$_bv/?p=2&share_source=copy');
      expect(input.bvid, _bv);
      expect(input.page, 2);
      expect(
          BilibiliService.parseInput('b23.tv/abc').shortLink!.scheme, 'https');
      expect(
          BilibiliService.parseInput('m.bilibili.com/video/$_bv?p=2').page, 2);
    });
    for (final input in [
      '',
      'https://evil.test/video/$_bv',
      'https://www.bilibili.com.evil.test/video/$_bv',
      'https://evil.test/$_bv',
      'https://user@www.bilibili.com/video/$_bv',
      'https://www.bilibili.com:444/video/$_bv',
      'https://www.bilibili.com/video/$_bv?p=0',
      'https://www.bilibili.com/video/$_bv?p=abc',
      'file:///$_bv',
      '//evil.test/$_bv'
    ]) {
      test('rejects unsafe or malformed input: $input', () {
        expect(() => BilibiliService.parseInput(input),
            throwsA(_kind(BiliErrorKind.input)));
      });
    }
    test('short-link redirects preserve part and never carry session cookies',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        _cookieKey:
            jsonEncode({'SESSDATA': 'test-session', 'bili_jct': 'test-csrf'})
      });
      final adapter =
          _Adapter((o) => ResponseBody.fromString('', 302, headers: {
                'location': ['https://www.bilibili.com/video/$_bv?p=2']
              }));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await service.initialize();
      final target = await service.resolveInput('https://b23.tv/abc');
      expect(target.bvid, _bv);
      expect(target.page, 2);
      expect(adapter.requests.single.headers.containsKey('Cookie'), false);
      expect(adapter.requests.single.followRedirects, false);
    });
    for (final location in [
      'https://evil.test/$_bv',
      'http://www.bilibili.com/video/$_bv',
      'https://www.bilibili.com.evil.test/video/$_bv',
      'https://www.bilibili.com:444/video/$_bv'
    ]) {
      test('does not follow unsafe redirect $location', () async {
        final adapter =
            _Adapter((_) => ResponseBody.fromString('', 302, headers: {
                  'location': [location]
                }));
        final service = BilibiliService(adapter: adapter);
        addTearDown(service.dispose);
        await expectLater(service.resolveInput('https://b23.tv/abc'),
            throwsA(_kind(BiliErrorKind.input)));
        expect(adapter.requests, hasLength(1));
      });
    }
    test('short-link redirect loop is bounded', () async {
      final adapter =
          _Adapter((_) => ResponseBody.fromString('', 302, headers: {
                'location': ['/loop']
              }));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await expectLater(service.resolveInput('https://b23.tv/abc'),
          throwsA(isA<BiliException>()));
      expect(adapter.requests, hasLength(5));
    });
  });

  group('WBI and content', () {
    test('fixed canonical WBI vector is deterministic', () {
      final signed = BilibiliService.signWbi(
          {'foo': '114', 'bar': '514', 'baz': '1919810'},
          imgKey: _img, subKey: _sub, timestamp: 1702204169);
      // Independently cross-checked with System.Security.Cryptography.MD5.
      expect(signed['w_rid'], '6149fdadf571698ca7e6a567265cd0ee');
      expect(signed['wts'], '1702204169');
      expect(
          BilibiliService.signWbi(
              {'baz': '1919810', 'foo': '114', 'bar': '514'},
              imgKey: _img, subKey: _sub, timestamp: 1702204169),
          signed);
    });
    test(
        'WBI strips forbidden characters and old signatures without mutating input',
        () {
      final input = <String, dynamic>{
        'keyword': "a!'()* b",
        'w_rid': 'stale',
        'wts': 0
      };
      final signed = BilibiliService.signWbi(input,
          imgKey: _img, subKey: _sub, timestamp: 1);
      expect(signed['keyword'], 'a b');
      expect(signed['wts'], '1');
      expect(input['keyword'], "a!'()* b");
      expect(input['w_rid'], 'stale');
    });
    test(
        'parts and source_data round trip without credentials or playback URLs',
        () {
      final video = BiliVideo.fromJson(_video());
      expect(video.title, 'Test & video');
      expect(video.parts.length, 2);
      final part = video.parts[1];
      expect(part.cid, 1002);
      expect(part.page, 2);
      expect(part.duration.inSeconds, 60);
      final source = video.toSourceData(part: part);
      expect(source['cid'], 1002);
      expect(source['page'], 2);
      expect(source['title'], 'Examples');
      expect(source['url'], endsWith('?p=2'));
      final restored = BiliVideo.fromSourceData({'source_data': source});
      expect(restored.bvid, _bv);
      expect(restored.parts[1].cid, 1002);
      expect(restored.title, video.title);
      expect(restored.duration, video.duration);
      expect(jsonEncode(source), isNot(contains('SESSDATA')));
    });
    test(
        'signed search uses page/order and cached keys; BV search reads details',
        () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/nav')) return _json(_nav());
        if (o.uri.path.endsWith('/view')) return _data(_video());
        expect(o.uri.queryParameters['page'], '2');
        expect(o.uri.queryParameters['order'], 'pubdate');
        expect(
            o.uri.queryParameters['w_rid'], matches(RegExp('^[a-f0-9]{32}\$')));
        return _data({
          'result': [_video()],
          'numResults': 60,
          'numPages': 3
        });
      });
      final service = BilibiliService(
          adapter: adapter,
          clock: () => DateTime.fromMillisecondsSinceEpoch(1702204169000));
      addTearDown(service.dispose);
      final result = await service.search('test',
          page: 2, order: BiliSearchOrder.published);
      expect(result.items.single.bvid, _bv);
      expect(result.hasMore, true);
      expect(result.total, 60);
      await service.search('test', page: 2, order: BiliSearchOrder.published);
      expect(adapter.requests.where((r) => r.uri.path.endsWith('/nav')),
          hasLength(1));
      expect((await service.search(_bv)).items.single.parts, hasLength(2));
    });
  });

  group('Playback and text tracks', () {
    test('MP4 preserves all segments, actual quality, speed and safe headers',
        () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/nav')) return _json(_nav());
        expect(o.uri.queryParameters['fnval'], '0');
        expect(o.uri.queryParameters['qn'], '80');
        return _data({
          'quality': 64,
          'format': 'mp4',
          'accept_quality': [80, 64, 32],
          'durl': [
            {'url': 'https://v.bilivideo.com/one.mp4'},
            {'url': 'https://v.bilivideo.cn/two.mp4'}
          ]
        });
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final result = await service.resolvePlayback(_bv, 1002, speed: 1.5);
      expect(result.segments, hasLength(2));
      expect(result.isDash, false);
      expect(result.quality, 64);
      expect(result.requestedQuality, 80);
      expect(result.speed, 1.5);
      expect(result.headers['Referer'], 'https://www.bilibili.com/video/$_bv/');
      expect(result.headers.containsKey('Cookie'), false);
      expect(result.headers.containsKey('Authorization'), false);
    });
    test('DASH fallback includes separate audio and chooses requested quality',
        () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/nav')) return _json(_nav());
        if (o.uri.queryParameters['fnval'] == '0') return _data({});
        return _data({
          'accept_quality': [120, 80, 64],
          'dash': {
            'video': [
              for (final q in [64, 120, 80])
                {'id': q, 'baseUrl': 'https://v.bilivideo.com/$q.m4s'}
            ],
            'audio': [
              {
                'bandwidth': 128,
                'base_url': 'https://v.bilivideo.com/audio.m4s'
              }
            ],
          }
        });
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final result = await service.resolvePlayback(_bv, 1001);
      expect(result.isDash, true);
      expect(result.quality, 80);
      expect(result.videoUrl, endsWith('/80.m4s'));
      expect(result.audioUrl, endsWith('/audio.m4s'));
      expect(result.segments, isEmpty);
    });
    test('paid preview returns a permission error without alternative requests',
        () async {
      final adapter = _Adapter((o) => o.uri.path.endsWith('/nav')
          ? _json(_nav())
          : _data({'is_preview': 1}));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await expectLater(service.resolvePlayback(_bv, 1001),
          throwsA(_kind(BiliErrorKind.permission)));
      expect(adapter.requests, hasLength(2));
    });
    test('untrusted media URLs are not handed to the player', () async {
      final adapter = _Adapter((o) => o.uri.path.endsWith('/nav')
          ? _json(_nav())
          : _data({
              'durl': [
                {'url': 'https://bilivideo.com.evil.test/file'}
              ]
            }));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await expectLater(service.resolvePlayback(_bv, 1001),
          throwsA(_kind(BiliErrorKind.input)));
    });
    test('subtitle JSON and danmaku XML are read anonymously', () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/nav')) return _json(_nav());
        if (o.uri.path.endsWith('/v2')) {
          return _data({
            'subtitle': {
              'subtitles': [
                {
                  'id': 1,
                  'lan': 'en',
                  'lan_doc': 'English',
                  'subtitle_url': '//aisubtitle.hdslb.com/test.json'
                }
              ]
            }
          });
        }
        expect(o.headers.containsKey('Cookie'), false);
        if (o.uri.host == 'aisubtitle.hdslb.com') {
          return _json({
            'body': [
              {'from': 0.5, 'to': 2.5, 'content': 'Hello'}
            ]
          });
        }
        return ResponseBody.fromString(
            '<?xml version="1.0"?><i><d p="1,1,25,1">Hi</d></i>', 200);
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final tracks = await service.getSubtitles(_bv, 1002);
      expect(tracks.single.language, 'en');
      final body = await service.getSubtitleBody(tracks.single);
      expect(body.single.from, 0.5);
      expect(body.single.to, 2.5);
      expect(body.single.content, 'Hello');
      expect(await service.getDanmakuXml(1002), contains('<d p='));
      final before = adapter.requests.length;
      await expectLater(
          service.getSubtitleBody(const BiliSubtitle(
              id: '2',
              language: 'en',
              label: 'Bad',
              url: 'https://hdslb.com.evil.test/a')),
          throwsA(_kind(BiliErrorKind.input)));
      expect(adapter.requests, hasLength(before));
    });
  });

  group('Local account and safety', () {
    test('login migration validates before replacing and defaults to read only',
        () async {
      final adapter = _Adapter((o) => _json(_nav(
          loggedIn: o.headers['Cookie'].toString().contains('new-session'))));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await service.importLogin(jsonEncode({
        'cookies': {
          'SESSDATA': 'new-session',
          'bili_jct': 'csrf',
          'Authorization': 'forbidden'
        }
      }));
      expect(service.account?.mid, 42);
      expect(service.readOnly, true);
      final exported = jsonDecode(await service.exportLogin());
      expect(exported['cookies']['SESSDATA'], 'new-session');
      expect(exported['cookies'].containsKey('Authorization'), false);
      await expectLater(service.importLogin('SESSDATA=invalid; bili_jct=csrf'),
          throwsA(isA<BiliException>()));
      expect(jsonDecode(await service.exportLogin())['cookies']['SESSDATA'],
          'new-session');
      expect(service.account?.mid, 42);
    });
    test('browser cookie export imports only trusted domain credentials',
        () async {
      final service = BilibiliService(
          adapter: _Adapter((_) => _json(_nav(loggedIn: true))));
      addTearDown(service.dispose);
      await service.importLogin(jsonEncode([
        {'name': 'SESSDATA', 'value': 'trusted', 'domain': '.bilibili.com'},
        {'name': 'bili_jct', 'value': 'bad', 'domain': '.evil.test'},
      ]));
      expect(jsonDecode(await service.exportLogin())['cookies'],
          {'SESSDATA': 'trusted'});
      await expectLater(service.importLogin('SESSDATA=bad\r\nInjected=yes'),
          throwsA(isA<BiliException>()));
      expect(jsonDecode(await service.exportLogin())['cookies']['SESSDATA'],
          'trusted');
    });
    test('initialization cannot restore cookies after concurrent local logout',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        _cookieKey: jsonEncode({'SESSDATA': 'old-session'}),
        _protectionKey: 'false'
      });
      final adapter = _Adapter((_) => _data(_video()));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final initialization = service.initialize();
      final logout = service.logout();
      await initialization;
      await logout;
      await service.getVideo(_bv);
      expect(adapter.requests.single.headers.containsKey('Cookie'), false);
      expect(service.readOnly, true);
    });
    test('protection changes serialize and the last command wins', () async {
      final service = BilibiliService(adapter: _Adapter((_) => _data({})));
      addTearDown(service.dispose);
      final disabling = service.setReadOnly(false);
      final enabling = service.setReadOnly(true);
      await disabling;
      await enabling;
      expect(service.readOnly, true);
      expect(
          await const FlutterSecureStorage().read(key: _protectionKey), 'true');
    });
    test('read-only prevents every account write before any request', () async {
      final adapter = _Adapter((_) => _data({}));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      for (final command in <Future<void> Function()>[
        () => service.setLiked(1, true),
        () => service.addCoins(1),
        () => service.updateFavorite(1, addFolderIds: [2]),
        () => service.setFollowing(1, true),
      ]) {
        await expectLater(command(), throwsA(_kind(BiliErrorKind.protection)));
      }
      expect(adapter.requests, isEmpty);
    });
    test(
        'explicit writes require session and CSRF; logout clears only local keys',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        _cookieKey:
            jsonEncode({'SESSDATA': 'fake-session', 'bili_jct': 'fake-csrf'}),
        'unrelated-token': 'preserve',
      });
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/nav')) return _json(_nav(loggedIn: true));
        expect(o.method, 'POST');
        expect(o.headers['Cookie'], contains('fake-session'));
        expect((o.data as Map)['csrf'], 'fake-csrf');
        return _data({});
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await service.initialize();
      await service.refreshAccount();
      await service.setReadOnly(false);
      await service.addCoins(123);
      expect(
          adapter.requests.last.contentType, Headers.formUrlEncodedContentType);
      final before = adapter.requests.length;
      await service.logout();
      expect(service.readOnly, true);
      expect(service.account, null);
      expect(adapter.requests.length, before);
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: _cookieKey), null);
      expect(await storage.read(key: _protectionKey), null);
      expect(await storage.read(key: 'unrelated-token'), 'preserve');
    });
    test(
        'QR status, verification and secure persistence; cookie never appears in metadata',
        () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/generate')) {
          return _data({
            'url': 'https://passport.bilibili.com/login?x=qr',
            'qrcode_key': 'fake-qr'
          });
        }
        if (o.uri.path.endsWith('/poll')) {
          return _json({
            'code': 0,
            'data': {'code': 0}
          }, headers: {
            'set-cookie': [
              'SESSDATA=new-session; Path=/; Secure',
              'bili_jct=new-csrf; Path=/; Secure',
              'unknown=ignore; Path=/'
            ],
          });
        }
        expect(o.headers['Cookie'], contains('new-session'));
        return _json(_nav(loggedIn: true));
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final qr = await service.createQrLogin();
      expect(await service.pollQrLogin(qr), BiliQrStatus.authenticated);
      expect(service.account!.mid, 42);
      expect(service.readOnly, true);
      final saved = await const FlutterSecureStorage().read(key: _cookieKey);
      expect(jsonDecode(saved!),
          {'SESSDATA': 'new-session', 'bili_jct': 'new-csrf'});
      expect(
          adapter.requests
              .where((o) => o.uri.host == 'passport.bilibili.com')
              .every((o) => !o.headers.containsKey('Cookie')),
          true);
      expect(qr.toString(), isNot(contains('fake-qr')));
    });
    for (final host in ['account.bilibili.com', 'passport.bilibili.com']) {
      test('official QR host $host is accepted without moving the poll API',
          () async {
        final url = 'https://$host/h5/account-h5/auth/scan-web?key=fake-qr';
        final adapter = _Adapter((o) {
          expect(o.uri.host, 'passport.bilibili.com');
          expect(o.headers.containsKey('Cookie'), isFalse);
          if (o.uri.path.endsWith('/generate')) {
            return _data({'url': url, 'qrcode_key': 'fake-qr'});
          }
          expect(o.uri.queryParameters['qrcode_key'], 'fake-qr');
          return _data({'code': 86101});
        });
        final service = BilibiliService(adapter: adapter);
        addTearDown(service.dispose);
        final qr = await service.createQrLogin();
        expect(qr.url, url);
        expect(await service.pollQrLogin(qr), BiliQrStatus.waiting);
      });
    }
    for (final url in [
      'http://account.bilibili.com/h5/account-h5/auth/scan-web',
      'https://account.bilibili.com:444/h5/account-h5/auth/scan-web',
      'https://account.bilibili.com.evil.test/login',
      'https://account.bilibili.com@evil.test/login',
      'https://user@account.bilibili.com/login',
      'https://evil.test/login',
      'https://sub.account.bilibili.com/login',
      '//account.bilibili.com/login',
      '/login',
      '',
    ]) {
      test('untrusted QR URL is rejected: $url', () async {
        final service = BilibiliService(
            adapter: _Adapter(
                (_) => _data({'url': url, 'qrcode_key': 'fake-secret'})));
        addTearDown(service.dispose);
        await expectLater(
            service.createQrLogin(),
            throwsA(isA<BiliException>().having((e) => e.message, 'message',
                allOf(contains('二维码无效'), isNot(contains('fake-secret'))))));
      });
    }
    for (final key in [
      null,
      '',
      '  ',
      12,
      {'key': 'fake'}
    ]) {
      test('invalid QR key type or empty value is rejected: $key', () async {
        final service = BilibiliService(
            adapter: _Adapter((_) => _data({
                  'url':
                      'https://account.bilibili.com/h5/account-h5/auth/scan-web',
                  'qrcode_key': key,
                })));
        addTearDown(service.dispose);
        await expectLater(
            service.createQrLogin(), throwsA(isA<BiliException>()));
      });
    }
    test(
        'folded Set-Cookie fields preserve session and csrf, including Expires commas',
        () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/generate')) {
          return _data({
            'url': 'https://passport.bilibili.com/login',
            'qrcode_key': 'folded-test'
          });
        }
        if (o.uri.path.endsWith('/poll')) {
          return _json({
            'code': 0,
            'data': {'code': 0}
          }, headers: {
            'set-cookie': [
              'SESSDATA=new-session; Expires=Wed, 21 Oct 2026 08:00:00 GMT; Path=/, bili_jct=new-csrf; Path=/'
            ]
          });
        }
        expect(o.headers['Cookie'], contains('SESSDATA=new-session'));
        expect(o.headers['Cookie'], contains('bili_jct=new-csrf'));
        return _json(_nav(loggedIn: true));
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      expect(await service.pollQrLogin(await service.createQrLogin()),
          BiliQrStatus.authenticated);
      expect(service.isLoggedIn, isTrue);
    });
    test('late QR response cannot restore a logged-out session', () async {
      final poll = Completer<ResponseBody>();
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/generate')) {
          return _data({
            'url': 'https://passport.bilibili.com/login',
            'qrcode_key': 'fake-qr'
          });
        }
        return poll.future;
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final qr = await service.createQrLogin();
      final result = service.pollQrLogin(qr);
      final expectation =
          expectLater(result, throwsA(_kind(BiliErrorKind.cancelled)));
      await service.logout();
      poll.complete(_json({
        'code': 0,
        'data': {'code': 0}
      }, headers: {
        'set-cookie': ['SESSDATA=late; Secure']
      }));
      await expectation;
      expect(service.account, null);
      expect(await const FlutterSecureStorage().read(key: _cookieKey), null);
    });
    test('network errors are classified without request/cookie leakage',
        () async {
      final adapter = _Adapter((o) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionTimeout,
          message: 'SESSDATA=secret request_token=secret'));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      try {
        await service.getVideo(_bv);
        fail('Expected error');
      } on BiliException catch (error) {
        expect(error.kind, BiliErrorKind.network);
        expect(error.message, contains('timed out'));
        expect(error.toString(), isNot(contains('secret')));
      }
    });
    test('permission error does not echo server payloads', () async {
      final adapter = _Adapter(
          (_) => _json({'code': -10403, 'message': 'SESSDATA=secret'}));
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await expectLater(
          service.getVideo(_bv),
          throwsA(_kind(BiliErrorKind.permission).having(
              (dynamic e) => e.message, 'message', isNot(contains('secret')))));
    });
  });

  group('Additional public protocol coverage', () {
    test('uploader and collection pagination map unified video models',
        () async {
      final adapter = _Adapter((o) {
        final path = o.uri.path;
        if (path.endsWith('/nav')) return _json(_nav());
        if (path.endsWith('/acc/info')) {
          return _data({'mid': 42, 'name': 'Teacher', 'sign': 'Statistics'});
        }
        if (path.endsWith('/arc/search')) {
          return _data({
            'list': {
              'vlist': [_video()]
            },
            'page': {'count': 45}
          });
        }
        if (path.endsWith('/seasons_series_list')) {
          return _data({
            'items_lists': {
              'seasons_list': [
                {
                  'meta': {
                    'season_id': 8,
                    'mid': 42,
                    'name': 'Course',
                    'total': 25
                  }
                }
              ]
            }
          });
        }
        return _data({
          'archives': [_video()],
          'meta': {'total': 25}
        });
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      expect((await service.getUploader(42)).name, 'Teacher');
      final videos = await service.getUploaderVideos(42,
          page: 2, order: BiliUploaderOrder.clicks);
      expect(videos.hasMore, true);
      expect(videos.items.single.bvid, _bv);
      expect(adapter.requests.last.uri.queryParameters['order'], 'click');
      final collections = await service.getCollections(42);
      expect(collections.items.single.id, 8);
      expect(collections.items.single.ownerMid, 42);
      final contents =
          await service.getCollectionVideos(42, 8, page: 2, reverse: true);
      expect(contents.hasMore, false);
      expect(contents.items.single.bvid, _bv);
      expect(adapter.requests.last.uri.queryParameters['sort_reverse'], 'true');
    });
    test('account favorites, follows and subscribed UGC seasons are paged',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        _cookieKey:
            jsonEncode({'SESSDATA': 'test-session', 'bili_jct': 'test-csrf'})
      });
      final adapter = _Adapter((o) {
        final path = o.uri.path;
        if (path.endsWith('/nav')) return _json(_nav(loggedIn: true));
        if (path.endsWith('/list-all')) {
          return _data({
            'list': [
              {'id': 3, 'title': 'Study', 'media_count': 22}
            ]
          });
        }
        if (path.endsWith('/resource/list')) {
          return _data({
            'medias': [_video()],
            'has_more': true,
            'info': {'media_count': 22}
          });
        }
        if (path.endsWith('/followings')) {
          return _data({
            'list': [
              {'mid': 43, 'uname': 'Teacher'}
            ],
            'total': 21
          });
        }
        return _data({
          'list': [
            {
              'id': 8,
              'type': 21,
              'title': 'Course',
              'media_count': 25,
              'upper': {'mid': 43}
            },
            {'id': 9, 'type': 11, 'title': 'Not a UGC season'}
          ],
          'count': 22
        });
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      await service.initialize();
      await service.refreshAccount();
      expect((await service.getFavoriteFolders()).single.id, 3);
      final favorites = await service.getFavoriteVideos(3);
      expect(favorites.hasMore, true);
      expect(favorites.items.single.bvid, _bv);
      final followings = await service.getFollowings();
      expect(followings.items.single.mid, 43);
      expect(followings.hasMore, true);
      final subscribed = await service.getSubscribedCollections();
      expect(subscribed.items.single.id, 8);
      expect(subscribed.items.single.ownerMid, 43);
      expect(subscribed.hasMore, true);
      expect(service.readOnly, true);
      expect(adapter.requests.every((o) => o.method == 'GET'), true);
    });
    test('FLV is not mislabeled MP4; known HTTP CDN URLs are upgraded to TLS',
        () async {
      final adapter = _Adapter((o) {
        if (o.uri.path.endsWith('/nav')) return _json(_nav());
        if (o.uri.queryParameters['fnval'] == '0') {
          return _data({
            'format': 'flv',
            'durl': [
              {'url': 'http://v.bilivideo.com/file.flv'}
            ]
          });
        }
        return _data({
          'dash': {
            'video': [
              {'id': 80, 'baseUrl': 'http://v.bilivideo.com/video.m4s'}
            ],
            'audio': [
              {'baseUrl': 'http://v.bilivideo.com/audio.m4s'}
            ]
          }
        });
      });
      final service = BilibiliService(adapter: adapter);
      addTearDown(service.dispose);
      final playback = await service.resolvePlayback(_bv, 1001);
      expect(playback.isDash, true);
      expect(playback.segments, isEmpty);
      expect(playback.videoUrl, startsWith('https://'));
      expect(playback.audioUrl, startsWith('https://'));
    });
    for (final entry in {
      86101: BiliQrStatus.waiting,
      86090: BiliQrStatus.scanned,
      86038: BiliQrStatus.expired
    }.entries) {
      test('QR status ${entry.key} does not persist credentials', () async {
        final adapter = _Adapter((o) => o.uri.path.endsWith('/generate')
            ? _data({
                'url': 'https://passport.bilibili.com/login',
                'qrcode_key': 'fake-qr'
              })
            : _data({'code': entry.key}));
        final service = BilibiliService(adapter: adapter);
        addTearDown(service.dispose);
        final qr = await service.createQrLogin();
        expect(await service.pollQrLogin(qr), entry.value);
        expect(await const FlutterSecureStorage().read(key: _cookieKey), null);
      });
    }
    test('invalid JSON and status payloads are not reported as success',
        () async {
      for (final response in [
        ResponseBody.fromString('<html>Gateway</html>', 200),
        _json({'code': null}),
        _json({'data': {}})
      ]) {
        final service = BilibiliService(adapter: _Adapter((_) => response));
        await expectLater(service.getVideo(_bv), throwsA(isA<BiliException>()));
        service.dispose();
      }
    });
  });

  testWidgets('Chinese account labels and protection confirmation',
      (tester) async {
    final service = BilibiliService(adapter: _Adapter((_) => _data({})));
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: BilibiliAccountView(
            service: service,
            qrBuilder: (_, __) => const SizedBox(),
            onAdd: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('账号只读保护'), findsOneWidget);
    expect(find.text('我的收藏夹'), findsOneWidget);
    expect(find.text('我的关注'), findsOneWidget);
    expect(find.text('订阅的合集'), findsOneWidget);
    expect(find.byTooltip('刷新账号'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('关闭账号只读保护？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.readOnly, true);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.readOnly, false);
    expect(tester.takeException(), null);
  });

  testWidgets('Chinese QR waiting, scanned and expired states', (tester) async {
    var pollCount = 0;
    final service = BilibiliService(adapter: _Adapter((o) {
      if (o.uri.path.endsWith('/generate')) {
        return _data({
          'url': 'https://account.bilibili.com/h5/account-h5/auth/scan-web',
          'qrcode_key': 'fake-qr'
        });
      }
      return _data({'code': ++pollCount == 1 ? 86090 : 86038});
    }));
    addTearDown(service.dispose);
    String? renderedUrl;
    await tester.pumpWidget(MaterialApp(
        home: BilibiliAccountView(
            service: service,
            qrBuilder: (_, url) {
              renderedUrl = url;
              return const SizedBox();
            },
            onAdd: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫码登录'));
    await tester.pumpAndSettle();
    expect(renderedUrl,
        'https://account.bilibili.com/h5/account-h5/auth/scan-web');
    expect(find.text('等待扫码'), findsWidgets);
    expect(find.text('刷新二维码'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('已扫码，等待确认'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('二维码已过期'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chinese account command labels preserve explicit like command',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      _cookieKey:
          jsonEncode({'SESSDATA': 'test-session', 'bili_jct': 'test-csrf'}),
      _protectionKey: 'false',
    });
    final adapter = _Adapter((o) {
      if (o.uri.path.endsWith('/nav')) return _json(_nav(loggedIn: true));
      return _data(o.method == 'POST' ? {} : _video());
    });
    final service = BilibiliService(adapter: adapter);
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: BilibiliAccountView(
            service: service,
            qrBuilder: (_, __) => const SizedBox(),
            onAdd: (_) {})));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _bv);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('综合排序'), findsOneWidget);
    expect(find.text('排序方式'), findsOneWidget);
    await tester.tap(find.text('Test & video'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('账号操作'));
    await tester.pumpAndSettle();
    for (final label in [
      '点赞',
      '取消点赞',
      '投 1 枚硬币',
      '投 2 枚硬币',
      '收藏',
      '取消收藏',
      '关注',
      '取消关注'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('点赞'));
    // The command remains busy until its confirmation dialog is answered.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认在 B 站点赞？'), findsOneWidget);
    expect(adapter.requests.where((o) => o.method == 'POST'), isEmpty);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('点赞成功'), findsOneWidget);
    final command = adapter.requests.singleWhere((o) => o.method == 'POST');
    expect(command.uri.path, '/x/web-interface/archive/like');
    expect((command.data as Map)['like'], 1);
    expect(tester.takeException(), null);
  });

  for (final size in [const Size(320, 720), const Size(1440, 900)]) {
    testWidgets('account search and selected part callback at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service =
          BilibiliService(adapter: _Adapter((_) => _data(_video())));
      addTearDown(service.dispose);
      final added = <Map<String, dynamic>>[];
      await tester.pumpWidget(MaterialApp(
          home: BilibiliAccountView(
              service: service,
              qrBuilder: (_, __) => const SizedBox(),
              onAdd: added.add)));
      await tester.pumpAndSettle();
      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('账号只读保护'), findsOneWidget);
      await tester.enterText(find.byType(TextField), _bv);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test & video'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('P2  Examples'), 250);
      await tester.tap(find.byTooltip('将此分P加入学习列表').last);
      await tester.pumpAndSettle();
      expect(added.single['cid'], 1002);
      expect(added.single['source'], 'bilibili');
      expect(find.text('已加入学习列表'), findsOneWidget);
      expect(tester.takeException(), null);
    });
  }
}
