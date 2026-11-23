import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/study_model.dart';
import '../values/app_constants.dart';
import 'api_client.dart';
import 'bilibili_service.dart';
import 'device_integration_service.dart';
import 'study_preferences.dart';
import 'study_subscription_check.dart' as checker;
import 'study_subscription_scheduler.dart';

/// Referenced by the Android JobService, not by the visible app's main().
@pragma('vm:entry-point')
Future<void> studyBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final bili = BilibiliService();
  var cancelled = false;
  try {
    final token =
        await const FlutterSecureStorage().read(key: AppConstants.tokenKey);
    if (token == null || token.isEmpty) return;
    api.setToken(token);
    await (() async {
      final profile = studyMap((await api.get('/auth/profile')).data);
      final id = studyInt(profile['id']);
      if (id <= 0) return;
      final raw = studyMap((await api.get('/study/preferences')).data);
      final preferences = StudyPreferences.fromJson(raw);
      if (!preferences.subscriptionBackground || cancelled) return;
      final subscriptions =
          studyRows((await api.get('/study/subscriptions')).data)
              .map(StudySubscription.fromJson)
              .toList();
      await checker.StudySubscriptionCheck(api: api, bili: bili)
          .run(subscriptions, cancelled: () => cancelled);
      if (!preferences.subscriptionNotifications || cancelled) return;
      final updates = studyRows((await api.get('/study/updates')).data)
          .map(StudyUpdate.fromJson);
      final scope =
          sha256.convert(utf8.encode('${api.baseUrl}:$id')).toString();
      final key = StudySubscriptionScheduler.deliveredIdsKey(scope);
      final storage = await SharedPreferences.getInstance();
      await storage.reload();
      if ((storage.getInt('study_focus_until_$scope') ?? 0) >
          DateTime.now().millisecondsSinceEpoch) {
        return;
      }
      final delivered = (storage.getStringList(key) ?? []).toSet();
      final fresh = updates
          .where((u) => !u.read && !delivered.contains('${u.id}'))
          .toList();
      if (fresh.isEmpty || cancelled) return;
      if (await DeviceIntegrationService.showStudyNotification(
          title: fresh.length == 1 ? fresh.single.title : '学习订阅有新内容',
          count: fresh.length)) {
        delivered.addAll(fresh.map((u) => '${u.id}'));
        await storage.setStringList(key, delivered.toList());
      }
    })()
        .timeout(const Duration(seconds: 65), onTimeout: () {
      cancelled = true;
    });
  } catch (_) {
    // A scheduled check is best effort. Do not log account data or media URLs.
  } finally {
    cancelled = true;
    bili.dispose();
    api.setToken(null);
    await DeviceIntegrationService.completeStudyBackground();
  }
}
