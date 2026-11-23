import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'api_client.dart';
import 'auth_service.dart';

typedef StudyPreferencesGuard = Future<bool> Function(
    StudyPreferences previous, StudyPreferences next);
typedef StudyPreferencesCommit = Future<void> Function(
    StudyPreferences previous, StudyPreferences next);

@immutable
class StudyPreferences {
  const StudyPreferences._({
    this.cardOrder = defaultCardOrder,
    this.hiddenCards = const [],
    this.subscriptionNotifications = false,
    this.subscriptionBackground = false,
    this.doubleTapLeft = 'seek_backward',
    this.doubleTapCenter = 'play_pause',
    this.doubleTapRight = 'seek_forward',
    this.doubleTapLeftWidth = 0.35,
    this.doubleTapRightWidth = 0.35,
    this.doubleTapHeight = 1,
    this.seekSeconds = 10,
    this.longPressRate = 3,
    this.layout = 'auto',
  });

  factory StudyPreferences({
    List<String> cardOrder = defaultCardOrder,
    List<String> hiddenCards = const [],
    bool subscriptionNotifications = false,
    bool subscriptionBackground = false,
    String doubleTapLeft = 'seek_backward',
    String doubleTapCenter = 'play_pause',
    String doubleTapRight = 'seek_forward',
    double doubleTapLeftWidth = 0.35,
    double doubleTapRightWidth = 0.35,
    double doubleTapHeight = 1,
    int seekSeconds = 10,
    double longPressRate = 3,
    String layout = 'auto',
  }) =>
      StudyPreferences.fromJson({
        'card_order': cardOrder,
        'hidden_cards': hiddenCards,
        'subscription_notifications': subscriptionNotifications,
        'subscription_background': subscriptionBackground,
        'double_tap_left': doubleTapLeft,
        'double_tap_center': doubleTapCenter,
        'double_tap_right': doubleTapRight,
        'double_tap_left_width': doubleTapLeftWidth,
        'double_tap_right_width': doubleTapRightWidth,
        'double_tap_height': doubleTapHeight,
        'seek_seconds': seekSeconds,
        'long_press_rate': longPressRate,
        'layout': layout,
      });

  static const defaults = StudyPreferences._();
  static const defaultCardOrder = [
    'continue',
    'lists',
    'focus',
    'updates',
    'shortcuts'
  ];
  static const actions = [
    'seek_backward',
    'seek_forward',
    'play_pause',
    'none'
  ];
  static const layouts = ['auto', 'portrait', 'landscape'];
  static const fields = {
    'card_order',
    'hidden_cards',
    'subscription_notifications',
    'subscription_background',
    'double_tap_left',
    'double_tap_center',
    'double_tap_right',
    'double_tap_left_width',
    'double_tap_right_width',
    'double_tap_height',
    'seek_seconds',
    'long_press_rate',
    'layout',
  };

  final List<String> cardOrder;
  final List<String> hiddenCards;
  final bool subscriptionNotifications;
  final bool subscriptionBackground;
  final String doubleTapLeft;
  final String doubleTapCenter;
  final String doubleTapRight;
  final double doubleTapLeftWidth;
  final double doubleTapRightWidth;
  final double doubleTapHeight;
  final int seekSeconds;
  final double longPressRate;
  final String layout;

  List<String> get visibleCards =>
      List.unmodifiable(cardOrder.where((id) => !hiddenCards.contains(id)));

  /// dx/dy are normalized to the visible player viewport. The vertical active
  /// band is centered, matching the settings preview; invalid points do nothing.
  String doubleTapActionAt(double dx, double dy) {
    if (!dx.isFinite || !dy.isFinite || dx < 0 || dx > 1 || dy < 0 || dy > 1) {
      return 'none';
    }
    final top = (1 - doubleTapHeight) / 2;
    if (dy < top || dy > 1 - top) {
      return 'none';
    }
    if (dx <= doubleTapLeftWidth) {
      return doubleTapLeft;
    }
    if (dx >= 1 - doubleTapRightWidth) {
      return doubleTapRight;
    }
    return doubleTapCenter;
  }

  factory StudyPreferences.fromJson(Map<String, dynamic> json) {
    List<String> cards(String key) {
      final value =
          json[key] ?? (key == 'card_order' ? defaultCardOrder : const []);
      if (value is! List ||
          value.any((id) => !defaultCardOrder.contains(id)) ||
          value.toSet().length != value.length) {
        throw const FormatException('首页设置无效');
      }
      return List<String>.from(value);
    }

    bool flag(String key) {
      final value = json[key] ?? false;
      if (value is! bool) throw const FormatException('订阅设置无效');
      return value;
    }

    String option(String key, List<String> choices, String fallback) {
      final value = json[key] ?? fallback;
      if (value is! String || !choices.contains(value)) {
        throw const FormatException('播放设置无效');
      }
      return value;
    }

    double dimension(String key, double fallback, double min, double max) {
      final value = json[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('双击区域尺寸超出范围');
      }
      return value.toDouble();
    }

    final seek = json['seek_seconds'] ?? 10;
    final rate = json['long_press_rate'] ?? 3;
    if (seek is! num ||
        !seek.isFinite ||
        seek % 1 != 0 ||
        seek < 1 ||
        seek > 120 ||
        rate is! num ||
        !rate.isFinite ||
        rate < 1 ||
        rate > 4) {
      throw const FormatException('播放数值超出范围');
    }
    final order = cards('card_order');
    return StudyPreferences._(
      cardOrder: List.unmodifiable(
          [...order, ...defaultCardOrder.where((id) => !order.contains(id))]),
      hiddenCards: List.unmodifiable(cards('hidden_cards')),
      subscriptionNotifications: flag('subscription_notifications'),
      subscriptionBackground: flag('subscription_background'),
      doubleTapLeft: option('double_tap_left', actions, 'seek_backward'),
      doubleTapCenter: option('double_tap_center', actions, 'play_pause'),
      doubleTapRight: option('double_tap_right', actions, 'seek_forward'),
      doubleTapLeftWidth: dimension('double_tap_left_width', 0.35, 0.1, 0.45),
      doubleTapRightWidth: dimension('double_tap_right_width', 0.35, 0.1, 0.45),
      doubleTapHeight: dimension('double_tap_height', 1, 0.2, 1),
      seekSeconds: seek.toInt(),
      longPressRate: rate.toDouble(),
      layout: option('layout', layouts, 'auto'),
    );
  }

  Map<String, dynamic> toJson() => {
        'card_order': cardOrder,
        'hidden_cards': hiddenCards,
        'subscription_notifications': subscriptionNotifications,
        'subscription_background': subscriptionBackground,
        'double_tap_left': doubleTapLeft,
        'double_tap_center': doubleTapCenter,
        'double_tap_right': doubleTapRight,
        'double_tap_left_width': doubleTapLeftWidth,
        'double_tap_right_width': doubleTapRightWidth,
        'double_tap_height': doubleTapHeight,
        'seek_seconds': seekSeconds,
        'long_press_rate': longPressRate,
        'layout': layout,
      };

  StudyPreferences copyWith({
    List<String>? cardOrder,
    List<String>? hiddenCards,
    bool? subscriptionNotifications,
    bool? subscriptionBackground,
    String? doubleTapLeft,
    String? doubleTapCenter,
    String? doubleTapRight,
    double? doubleTapLeftWidth,
    double? doubleTapRightWidth,
    double? doubleTapHeight,
    int? seekSeconds,
    double? longPressRate,
    String? layout,
  }) =>
      StudyPreferences(
        cardOrder: cardOrder ?? this.cardOrder,
        hiddenCards: hiddenCards ?? this.hiddenCards,
        subscriptionNotifications:
            subscriptionNotifications ?? this.subscriptionNotifications,
        subscriptionBackground:
            subscriptionBackground ?? this.subscriptionBackground,
        doubleTapLeft: doubleTapLeft ?? this.doubleTapLeft,
        doubleTapCenter: doubleTapCenter ?? this.doubleTapCenter,
        doubleTapRight: doubleTapRight ?? this.doubleTapRight,
        doubleTapLeftWidth: doubleTapLeftWidth ?? this.doubleTapLeftWidth,
        doubleTapRightWidth: doubleTapRightWidth ?? this.doubleTapRightWidth,
        doubleTapHeight: doubleTapHeight ?? this.doubleTapHeight,
        seekSeconds: seekSeconds ?? this.seekSeconds,
        longPressRate: longPressRate ?? this.longPressRate,
        layout: layout ?? this.layout,
      );

  @override
  bool operator ==(Object other) =>
      other is StudyPreferences &&
      listEquals(cardOrder, other.cardOrder) &&
      listEquals(hiddenCards, other.hiddenCards) &&
      subscriptionNotifications == other.subscriptionNotifications &&
      subscriptionBackground == other.subscriptionBackground &&
      doubleTapLeft == other.doubleTapLeft &&
      doubleTapCenter == other.doubleTapCenter &&
      doubleTapRight == other.doubleTapRight &&
      doubleTapLeftWidth == other.doubleTapLeftWidth &&
      doubleTapRightWidth == other.doubleTapRightWidth &&
      doubleTapHeight == other.doubleTapHeight &&
      seekSeconds == other.seekSeconds &&
      longPressRate == other.longPressRate &&
      layout == other.layout;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(cardOrder),
      Object.hashAll(hiddenCards),
      subscriptionNotifications,
      subscriptionBackground,
      doubleTapLeft,
      doubleTapCenter,
      doubleTapRight,
      doubleTapLeftWidth,
      doubleTapRightWidth,
      doubleTapHeight,
      seekSeconds,
      longPressRate,
      layout);
}

/// Server-backed draft; no credentials, URLs, or unrelated settings are exported.
class StudyPreferencesController extends ChangeNotifier {
  StudyPreferencesController(
      {ApiClient? api,
      String? Function()? scope,
      this.beforeSave,
      this.afterSave})
      : _api = api ?? ApiClient(),
        _scopeOverride = scope;

  final ApiClient _api;
  final String? Function()? _scopeOverride;
  final StudyPreferencesGuard? beforeSave;
  final StudyPreferencesCommit? afterSave;
  StudyPreferences _draft = StudyPreferences.defaults;
  StudyPreferences _saved = StudyPreferences.defaults;
  String? _loadedScope;
  bool _ready = false;
  bool _disposed = false;
  bool _loading = false;
  bool _saving = false;
  int _generation = 0;
  int _revision = 0;
  String? _error;
  String? _integrationError;

  String? get scopeKey {
    final override = _scopeOverride;
    if (override != null) return override();
    if (!Get.isRegistered<AuthService>()) return null;
    final auth = Get.find<AuthService>();
    final id = auth.user.value?.id;
    if (!auth.isAuthenticated.value || id == null) return null;
    return sha256.convert(utf8.encode('${_api.baseUrl}:$id')).toString();
  }

  bool get isLoaded =>
      !_disposed && _ready && scopeKey != null && scopeKey == _loadedScope;
  StudyPreferences get value => isLoaded ? _draft : StudyPreferences.defaults;
  StudyPreferences get savedValue =>
      isLoaded ? _saved : StudyPreferences.defaults;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get dirty => isLoaded && _draft != _saved;
  String? get error => _error;
  String? get integrationError => _integrationError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation, String scope) =>
      !_disposed && generation == _generation && scopeKey == scope;

  Future<bool> load({bool discardChanges = false}) async {
    if (_disposed || _saving) return false;
    if (dirty && !discardChanges) {
      _error = '请先保存或放弃未保存的设置';
      _notify();
      return false;
    }
    final generation = ++_generation;
    final scope = scopeKey;
    _loadedScope = scope;
    _ready = false;
    _draft = _saved = StudyPreferences.defaults;
    _error = _integrationError = null;
    _loading = scope != null;
    _notify();
    if (scope == null) {
      _error = '请先登录';
      _notify();
      return false;
    }
    try {
      final response = await _api.get('/study/preferences');
      if (!_current(generation, scope)) return false;
      _draft = _saved = _decodeResponse(response.data);
      _ready = true;
      return true;
    } catch (error) {
      if (_current(generation, scope)) _error = _safeError(error);
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  void update(StudyPreferences next) {
    if (!isLoaded) return;
    _draft = next;
    _revision++;
    _error = null;
    _notify();
  }

  void resetDraft() => update(StudyPreferences.defaults);
  void discardDraft() => update(savedValue);

  void reorderCards(int oldIndex, int newIndex) {
    final order = value.cardOrder.toList();
    if (oldIndex < 0 ||
        oldIndex >= order.length ||
        newIndex < 0 ||
        newIndex > order.length) {
      return;
    }
    if (newIndex > oldIndex) newIndex--;
    order.insert(newIndex, order.removeAt(oldIndex));
    update(value.copyWith(cardOrder: order));
  }

  void setCardVisible(String id, bool visible) {
    if (!StudyPreferences.defaultCardOrder.contains(id)) return;
    final hidden = value.hiddenCards.toSet();
    visible ? hidden.remove(id) : hidden.add(id);
    update(value.copyWith(hiddenCards: hidden.toList()));
  }

  Future<bool> save() async {
    if (!isLoaded || _saving || _loading) return false;
    final scope = scopeKey!;
    final generation = _generation;
    final revision = _revision;
    final previous = _saved;
    final requested = _draft;
    _saving = true;
    _error = _integrationError = null;
    _notify();
    try {
      if (beforeSave != null && !await beforeSave!(previous, requested)) {
        if (_current(generation, scope)) _error = '未获授权，设置未保存';
        return false;
      }
      if (!_current(generation, scope)) return false;
      final response =
          await _api.put('/study/preferences', data: requested.toJson());
      if (!_current(generation, scope)) return false;
      _saved =
          response.data == null ? requested : _decodeResponse(response.data);
      if (_revision == revision) _draft = _saved;
      try {
        await afterSave?.call(previous, _saved);
      } catch (_) {
        if (_current(generation, scope)) _integrationError = '设置已保存，设备配置同步失败';
      }
      return _current(generation, scope);
    } catch (error) {
      if (_current(generation, scope)) _error = _safeError(error);
      return false;
    } finally {
      if (!_disposed) {
        _saving = false;
        _notify();
      }
    }
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'format': 'focusbili-study-preferences',
        'version': 1,
        'preferences': value.toJson(),
      });

  void importJson(String text) {
    if (!isLoaded) throw const FormatException('请先加载当前账号设置');
    if (text.length > 32768) throw const FormatException('设置文件过大');
    dynamic raw;
    try {
      raw = jsonDecode(text);
    } catch (_) {
      throw const FormatException('设置 JSON 无效');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('设置 JSON 必须为对象');
    }
    Map<String, dynamic> payload = raw;
    if (raw.containsKey('format')) {
      if (raw['format'] != 'focusbili-study-preferences' ||
          raw['version'] != 1 ||
          raw.keys.any(
              (key) => !{'format', 'version', 'preferences'}.contains(key)) ||
          raw['preferences'] is! Map<String, dynamic>) {
        throw const FormatException('不支持的设置文件');
      }
      payload = raw['preferences'] as Map<String, dynamic>;
    }
    if (payload.keys.any((key) => !StudyPreferences.fields.contains(key))) {
      throw const FormatException('文件含有不支持的设置字段');
    }
    update(StudyPreferences.fromJson(payload));
  }

  StudyPreferences _decodeResponse(dynamic raw) {
    if (raw is Map && raw['data'] is Map) raw = raw['data'];
    if (raw is! Map) throw const FormatException('设置响应格式无效');
    if (!raw.containsKey('card_order') &&
        raw.keys.any({
          'home_card_order',
          'home_hidden_cards',
          'notifications_enabled',
          'background_refresh_enabled',
          'double_tap_seek_seconds',
          'long_press_speed',
        }.contains)) {
      throw const FormatException('设置服务契约不兼容');
    }
    return StudyPreferences.fromJson(Map<String, dynamic>.from(raw));
  }

  String _safeError(Object error) {
    if (error is ApiException &&
        (error.statusCode == 404 || error.statusCode == 405)) {
      return '当前服务器尚不支持学习设置';
    }
    if (error is ApiException && error.statusCode == 401) return '登录已过期，请重新登录';
    if (error is FormatException) return '设置数据无效，未应用更改';
    return '设置同步失败，请稍后重试';
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
