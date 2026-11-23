import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mpv;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/video_model.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/device_integration_service.dart';
import '../../../../core/services/bilibili_service.dart';
import '../../../../core/services/study_media_cache.dart';
import '../../../../core/services/study_offline_assets.dart';
import '../../../../core/services/study_progress_sync.dart';
import '../../../../core/services/study_preferences.dart';
import '../../../../core/values/api_endpoints.dart';

class DanmakuCue {
  const DanmakuCue({
    required this.start,
    required this.text,
    this.color,
    this.lane = 0,
  });

  final Duration start;
  final String text;
  final int? color;
  final int lane;
}

class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

class _AssDialogue {
  const _AssDialogue({
    required this.start,
    required this.end,
    required this.text,
  });

  final String start;
  final String end;
  final String text;
}

class VideoController extends GetxController {
  VideoController({
    ApiClient? apiClient,
    StudyMediaCache? mediaCache,
    Player Function()? playerFactory,
    mpv.VideoController? Function(Player)? videoControllerFactory,
    Duration dashReadyTimeout = const Duration(seconds: 15),
  })  : _apiClient = apiClient ?? ApiClient(),
        _mediaCache = mediaCache ?? StudyMediaCache.instance,
        _playerFactory = playerFactory ?? Player.new,
        _videoControllerFactory =
            videoControllerFactory ?? mpv.VideoController.new,
        _dashReadyTimeout = dashReadyTimeout;

  final ApiClient _apiClient;
  final StudyMediaCache _mediaCache;
  final Player Function() _playerFactory;
  final mpv.VideoController? Function(Player) _videoControllerFactory;
  final Duration _dashReadyTimeout;
  final BilibiliService _fallbackBilibili = BilibiliService();
  BilibiliService? studyBilibili;
  BilibiliService get _bilibili => studyBilibili ?? _fallbackBilibili;
  final playbackError = ''.obs;
  final activeVideo = Rxn<Video>();
  final playbackRate = 1.0.obs;
  final playbackQuality = 80.obs;
  final availableQualities = <int>[].obs;
  final biliSubtitles = <BiliSubtitle>[].obs;
  final autoNext = true.obs;
  final doubleTapSeconds = 10.obs;
  final doubleTapLeft = 'seek_backward'.obs;
  final doubleTapRight = 'seek_forward'.obs;
  StudyPreferences _gesturePreferences = StudyPreferences.defaults;
  final preferredLayout = 'auto'.obs;
  final longPressRate = 2.0.obs;
  final listenMode = false.obs;
  final sleepMinutes = 0.obs;
  final repeatStart = Rxn<Duration>();
  final repeatEnd = Rxn<Duration>();
  final courseQueue = <Video>[].obs;
  Timer? _sleepTimer;

  // 可观察变量
  final isLoading = false.obs;
  final isVideoLoading = false.obs;
  final allVideos = <Video>[].obs;
  final videos = <Video>[].obs;
  final filteredVideos = <Video>[].obs;
  final relatedVideos = <Video>[].obs;
  final categories = <VideoCategory>[].obs;
  final selectedCategory = '全部'.obs;
  final selectedRootCategoryId = RxnInt();
  final selectedCategoryId = RxnInt();
  final selectedWatchStatus = 'unwatched'.obs;
  final expandedCategoryIds = <int>{}.obs;
  final sortBy = 'episode'.obs;
  final isPictureInPicture = false.obs;
  final subtitlesEnabled = true.obs;
  final danmakuEnabled = true.obs;
  final videoSidecars = <VideoSidecar>[].obs;
  final selectedSubtitleSidecar = Rxn<VideoSidecar>();
  final selectedDanmakuSidecar = Rxn<VideoSidecar>();
  final subtitleCues = <SubtitleCue>[].obs;
  final danmakuCues = <DanmakuCue>[].obs;
  final danmakuOpacity = 0.92.obs;
  final danmakuAreaRatio = 0.45.obs;
  final danmakuFontSize = 15.0.obs;
  final danmakuSpeed = 1.0.obs;

  Player? player;
  mpv.VideoController? mediaVideoController;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _pictureInPictureSubscription;
  StreamSubscription<String>? _videoActionSubscription;
  StreamSubscription<MediaPlaybackAction>? _mediaActionSubscription;
  final _mediaStateSubscriptions = <StreamSubscription<dynamic>>[];
  DateTime? _lastMediaStateAt;
  bool _nativeMediaReady = false;
  int? _activeVideoId;
  int? _loadingVideoId;
  int _playbackToken = 0;
  int _subtitleRequest = 0;
  int _danmakuRequest = 0;
  BiliSubtitle? _selectedBiliSubtitle;
  Completer<void> _playbackCancelled = Completer<void>();
  bool _closed = false;
  bool _resumeApplied = false;
  bool _studyPreferencesApplied = false;
  DateTime? _lastProgressSyncAt;

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadDanmakuSettings());
    unawaited(StudyProgressSync.instance.flush());
    _pictureInPictureSubscription =
        DeviceIntegrationService.pictureInPictureModeChanges.listen((active) {
      isPictureInPicture.value = active;
    });
    _videoActionSubscription =
        DeviceIntegrationService.videoActionEvents.listen((action) {
      if (action == 'togglePlayback') {
        togglePlayback();
      } else if (action == 'restoreApp') {
        isPictureInPicture.value = false;
      }
    });
    _mediaActionSubscription =
        DeviceIntegrationService.mediaPlaybackActions.listen((action) async {
      final current = activeVideo.value;
      final target = player;
      if (current == null ||
          target == null ||
          action.mediaId != _mediaId(current)) {
        return;
      }
      if (action.action == 'play') await target.play();
      if (action.action == 'pause') await target.pause();
      if (action.action == 'seekTo' && action.position != null) {
        await target.seek(action.position!);
      }
      if (action.action == 'stop') await stopCurrentPlayback();
    });
  }

  @override
  void onClose() {
    _closed = true;
    _invalidatePlayback();
    _pictureInPictureSubscription?.cancel();
    _videoActionSubscription?.cancel();
    _mediaActionSubscription?.cancel();
    _sleepTimer?.cancel();
    _fallbackBilibili.dispose();
    unawaited(_disposeVideoControllers());
    super.onClose();
  }

  int _invalidatePlayback() {
    _playbackToken++;
    _subtitleRequest++;
    _danmakuRequest++;
    _playbackCancelled.complete();
    _playbackCancelled = Completer<void>();
    return _playbackToken;
  }

  bool _isCurrent(int token, [Player? expectedPlayer]) =>
      !_closed &&
      !isClosed &&
      token == _playbackToken &&
      (expectedPlayer == null || identical(player, expectedPlayer));

  bool _isSubtitleCurrent(int token, Player expectedPlayer, int request) =>
      _isCurrent(token, expectedPlayer) &&
      request == _subtitleRequest &&
      subtitlesEnabled.value;

  bool _isDanmakuCurrent(int token, Player expectedPlayer, int request) =>
      _isCurrent(token, expectedPlayer) &&
      request == _danmakuRequest &&
      danmakuEnabled.value;

  Future<void> _disposeVideoControllers() async {
    _nativeMediaReady = false;
    for (final subscription in _mediaStateSubscriptions) {
      unawaited(subscription.cancel());
    }
    _mediaStateSubscriptions.clear();
    _lastMediaStateAt = null;
    unawaited(DeviceIntegrationService.setVideoPlaybackActive(false));
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _completedSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription = null;
    _completedSubscription = null;
    final previous = player;
    player = null;
    mediaVideoController = null;
    _activeVideoId = null;
    _resumeApplied = false;
    videoSidecars.clear();
    selectedSubtitleSidecar.value = null;
    _selectedBiliSubtitle = null;
    selectedDanmakuSidecar.value = null;
    subtitleCues.clear();
    danmakuCues.clear();
    biliSubtitles.clear();
    availableQualities.clear();
    repeatStart.value = null;
    repeatEnd.value = null;
    await previous?.dispose();
  }

  Future<void> stopCurrentPlayback() async {
    _invalidatePlayback();
    _saveCurrentPlaybackProgress();
    _loadingVideoId = null;
    isVideoLoading.value = false;
    await _disposeVideoControllers();
  }

  void _saveCurrentPlaybackProgress() {
    final activePlayer = player;
    final activeVideoId = _activeVideoId;
    if (activePlayer != null && activeVideoId != null) {
      final duration = activePlayer.state.duration;
      final position = activePlayer.state.position;
      if (duration.inMilliseconds > 0) {
        final percent =
            (position.inMilliseconds / duration.inMilliseconds * 100)
                .clamp(0, 100)
                .toDouble();
        _updateLocalVideoProgress(activeVideoId, percent, percent >= 95);
        unawaited(saveVideoProgress(activeVideoId, percent,
            completed: percent >= 95));
      }
    }
  }

  Future<void> requestFloatingPlaybackPermission() async {
    final granted =
        await DeviceIntegrationService.requestFloatingWindowPermission();
    if (granted) {
      Get.snackbar('悬浮播放', '已具备悬浮播放权限，返回桌面时会尝试继续播放');
    } else {
      Get.snackbar('悬浮播放', '请在系统设置中允许生统助手显示在其他应用上层');
    }
  }

  Future<void> enterFloatingPlayback() async {
    isPictureInPicture.value = true;
    final entered = await DeviceIntegrationService.enterPictureInPicture();
    if (!entered) {
      isPictureInPicture.value = false;
      Get.snackbar('悬浮播放', '当前设备暂不支持画中画，或系统未允许悬浮播放');
    }
  }

  Future<void> exitFloatingPlayback() async {
    final exited = await DeviceIntegrationService.exitPictureInPicture();
    if (exited) {
      isPictureInPicture.value = false;
    }
  }

  Future<void> togglePlayback() async {
    await player?.playOrPause();
  }

  String _mediaId(Video video) => '${video.source}:${video.id}:$_playbackToken';

  void _publishMediaState({bool force = false}) {
    final target = player;
    final video = activeVideo.value;
    if (!_nativeMediaReady || target == null || video == null || _closed) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastMediaStateAt != null &&
        now.difference(_lastMediaStateAt!).inSeconds < 2) {
      return;
    }
    _lastMediaStateAt = now;
    unawaited(DeviceIntegrationService.updateMediaPlaybackState(
        mediaId: _mediaId(video),
        title: video.title,
        artist: video.source == 'bilibili'
            ? '${video.sourceData['owner_name'] ?? ''}'
            : 'NAS 课程',
        playing: target.state.playing,
        buffering: target.state.buffering,
        position: target.state.position,
        duration: target.state.duration,
        speed: target.state.rate));
  }

  Future<void> setListenMode(bool value) async {
    listenMode.value = value;
    await DeviceIntegrationService.setAudioOnlyBackground(value);
    _publishMediaState(force: true);
  }

  void applyStudyPreferences(StudyPreferences preferences) {
    _studyPreferencesApplied = true;
    _gesturePreferences = preferences;
    doubleTapSeconds.value = preferences.seekSeconds;
    doubleTapLeft.value = preferences.doubleTapLeft;
    doubleTapRight.value = preferences.doubleTapRight;
    longPressRate.value = preferences.longPressRate;
    preferredLayout.value = preferences.layout;
  }

  Future<void> handleDoubleTap({required double x, required double y}) async {
    final targetPlayer = player;
    if (targetPlayer == null) return;
    final action = _gesturePreferences.doubleTapActionAt(x, y);
    if (action == 'play_pause') {
      await togglePlayback();
    } else if (action == 'seek_backward' || action == 'seek_forward') {
      final delta =
          (action == 'seek_backward' ? -1 : 1) * doubleTapSeconds.value;
      final target = (targetPlayer.state.position.inSeconds + delta)
          .clamp(0, targetPlayer.state.duration.inSeconds);
      await targetPlayer.seek(Duration(seconds: target));
    }
  }

  Future<void> setSubtitlesEnabled(bool value) async {
    final request = ++_subtitleRequest;
    final token = _playbackToken;
    subtitlesEnabled.value = value;
    final activePlayer = player;
    if (activePlayer == null || !_isCurrent(token, activePlayer)) return;
    if (!value) {
      await activePlayer.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    if (subtitleCues.isNotEmpty) {
      await activePlayer.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final sidecar = selectedSubtitleSidecar.value;
    if (sidecar != null) {
      await _loadSubtitleSidecar(activePlayer, sidecar, token, request);
    } else if (_selectedBiliSubtitle ?? biliSubtitles.firstOrNull
        case final subtitle?) {
      _selectedBiliSubtitle = subtitle;
      await _loadBiliSubtitle(activePlayer, subtitle, token, request);
    } else {
      await activePlayer.setSubtitleTrack(SubtitleTrack.auto());
    }
  }

  void setDanmakuEnabled(bool value) {
    final request = ++_danmakuRequest;
    danmakuEnabled.value = value;
    final activePlayer = player;
    final token = _playbackToken;
    if (value &&
        activePlayer != null &&
        danmakuCues.isEmpty &&
        _isCurrent(token, activePlayer)) {
      final sidecar = selectedDanmakuSidecar.value;
      if (sidecar != null) {
        unawaited(_loadDanmakuSidecar(activePlayer, sidecar, token, request));
      } else if (activeVideo.value?.source == 'bilibili') {
        final cid =
            int.tryParse('${activeVideo.value?.sourceData['cid']}') ?? 0;
        if (cid > 0) {
          unawaited(_loadBiliDanmaku(activePlayer, cid, token, request));
        }
      }
    }
    unawaited(saveDanmakuSettings());
  }

  void setDanmakuOpacity(double value) {
    danmakuOpacity.value = value.clamp(0.15, 1).toDouble();
  }

  void setDanmakuAreaRatio(double value) {
    danmakuAreaRatio.value = value.clamp(0.2, 1).toDouble();
  }

  void setDanmakuFontSize(double value) {
    danmakuFontSize.value = value.clamp(10, 28).toDouble();
  }

  void setDanmakuSpeed(double value) {
    danmakuSpeed.value = value.clamp(0.5, 2).toDouble();
  }

  Future<void> _loadDanmakuSettings() async {
    final prefs = await SharedPreferences.getInstance();
    playbackRate.value =
        (prefs.getDouble('study_playback_rate') ?? 1).clamp(0.5, 2);
    autoNext.value = prefs.getBool('study_auto_next') ?? true;
    if (!_studyPreferencesApplied) {
      doubleTapSeconds.value = prefs.getInt('study_double_tap_seconds') ?? 10;
      longPressRate.value = prefs.getDouble('study_long_press_rate') ?? 3;
    }
    danmakuEnabled.value = prefs.getBool('video_danmaku_enabled') ?? true;
    danmakuOpacity.value = (prefs.getDouble('video_danmaku_opacity') ?? 0.92)
        .clamp(0.15, 1)
        .toDouble();
    danmakuAreaRatio.value =
        (prefs.getDouble('video_danmaku_area_ratio') ?? 0.45)
            .clamp(0.2, 1)
            .toDouble();
    danmakuFontSize.value = (prefs.getDouble('video_danmaku_font_size') ?? 15)
        .clamp(10, 28)
        .toDouble();
    danmakuSpeed.value =
        (prefs.getDouble('video_danmaku_speed') ?? 1).clamp(0.5, 2).toDouble();
  }

  Future<void> saveDanmakuSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('video_danmaku_enabled', danmakuEnabled.value),
      prefs.setDouble('video_danmaku_opacity', danmakuOpacity.value),
      prefs.setDouble('video_danmaku_area_ratio', danmakuAreaRatio.value),
      prefs.setDouble('video_danmaku_font_size', danmakuFontSize.value),
      prefs.setDouble('video_danmaku_speed', danmakuSpeed.value),
    ]);
  }

  Future<void> selectSubtitleSidecar(VideoSidecar? sidecar) async {
    final request = ++_subtitleRequest;
    final token = _playbackToken;
    selectedSubtitleSidecar.value = sidecar;
    _selectedBiliSubtitle = null;
    final activePlayer = player;
    subtitleCues.clear();
    if (activePlayer == null ||
        !_isSubtitleCurrent(token, activePlayer, request)) {
      return;
    }
    if (sidecar == null) {
      await activePlayer.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    await _loadSubtitleSidecar(activePlayer, sidecar, token, request);
  }

  Future<void> selectDanmakuSidecar(VideoSidecar? sidecar) async {
    final request = ++_danmakuRequest;
    final token = _playbackToken;
    selectedDanmakuSidecar.value = sidecar;
    danmakuCues.clear();
    final activePlayer = player;
    if (sidecar == null ||
        activePlayer == null ||
        !_isDanmakuCurrent(token, activePlayer, request)) {
      return;
    }
    await _loadDanmakuSidecar(activePlayer, sidecar, token, request);
  }

  Future<void> loadVideos() async {
    isLoading.value = allVideos.isEmpty;

    try {
      final response = await _apiClient.get(
        ApiEndpoints.videos,
        queryParameters: {
          'limit': 1000,
          'sort': 'episode',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        allVideos.assignAll(data.map((json) => Video.fromJson(json)).toList());
        _applyVideoFilters();
      }
    } catch (e) {
      print('加载视频失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadVideoCategories() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.videoNasCategories);
      if (response.statusCode == 200) {
        final List<dynamic> data =
            response.data is List ? response.data : response.data['data'];
        categories.assignAll(
          data.map((json) => VideoCategory.fromJson(json)).toList(),
        );
        _ensureRootSelection();
      }
    } catch (e) {
      print('加载视频分类失败: $e');
      categories.clear();
      selectedRootCategoryId.value = null;
      selectedCategoryId.value = null;
      selectedCategory.value = '全部';
      expandedCategoryIds.clear();
    }
  }

  Future<void> loadVideoLibrary() async {
    await loadVideoCategories();
    await loadVideos();
  }

  Future<void> loadVideoDetail(int videoId, {Video? initial}) async {
    if (_closed || isClosed) return;
    if (_activeVideoId == videoId || _loadingVideoId == videoId) return;
    final token = _invalidatePlayback();
    _saveCurrentPlaybackProgress();
    final disposal = _disposeVideoControllers();
    _loadingVideoId = videoId;
    isVideoLoading.value = true;
    playbackError.value = '';
    Player? loadedPlayer;
    try {
      await disposal;
      if (!_isCurrent(token)) return;
      if (initial?.source == 'bilibili' ||
          initial?.sourceData['offline'] == true) {
        activeVideo.value = initial;
        relatedVideos
            .assignAll(courseQueue.where((item) => item.id != videoId));
        await _initializeVideoPlayer(initial!, token);
        return;
      }
      final response = await _apiClient.get(
        ApiEndpoints.videoDetail.replaceAll('{id}', videoId.toString()),
      );

      if (!_isCurrent(token)) return;
      if (response.statusCode == 200) {
        final video = Video.fromJson(response.data).copyWith(
          studyItemId: initial?.studyItemId,
          sourceData: initial?.sourceData,
        );
        activeVideo.value = video;
        _mergeVideo(video);
        loadedPlayer = await _initializeVideoPlayer(video, token);
        if (loadedPlayer == null || !_isCurrent(token, loadedPlayer)) return;
        if (video.nasCategoryId != null && allVideos.isEmpty) {
          final course = await _apiClient.get(ApiEndpoints.videos,
              queryParameters: {
                'nas_category_id': video.nasCategoryId,
                'sort': 'episode',
                'limit': 1000
              });
          if (!_isCurrent(token, loadedPlayer)) return;
          final rows = course.data['data'] as List;
          allVideos.assignAll(rows
              .map((row) => Video.fromJson(Map<String, dynamic>.from(row))));
        }
        relatedVideos.assignAll(
            courseVideosFor(video).where((item) => item.id != video.id));
      }
    } catch (e) {
      if (_isCurrent(token, loadedPlayer)) playbackError.value = '无法播放：$e';
    } finally {
      if (_isCurrent(token)) {
        _loadingVideoId = null;
        isVideoLoading.value = false;
      }
    }
  }

  Future<Player?> _initializeVideoPlayer(Video video, int token) async {
    if (!_isCurrent(token)) return null;
    _activeVideoId = video.id;
    _resumeApplied = false;
    _lastProgressSyncAt = null;
    isVideoLoading.value = true;

    Player? nextPlayer;
    final subtitleRequest = _subtitleRequest;
    final danmakuRequest = _danmakuRequest;
    try {
      nextPlayer = _playerFactory();
      player = nextPlayer;
      mediaVideoController = _videoControllerFactory(nextPlayer);
      var url = _apiClient.absoluteUrl(video.videoUrl);
      var headers = <String, String>{};
      BiliPlayback? resolvedBili;
      StudyCachedPlayback? cached;
      try {
        cached = await _mediaCache.localBundle(video);
      } catch (_) {}
      if (!_isCurrent(token, nextPlayer)) return null;
      if (cached != null) {
        url = cached.mediaUri;
        video = video.copyWith(sidecars: cached.sidecars);
      } else if (video.sourceData['offline'] == true) {
        throw StateError('离线缓存不完整，请重新下载');
      } else if (video.source == 'bilibili') {
        await _bilibili.initialize();
        if (!_isCurrent(token, nextPlayer)) return null;
        final bvid = video.sourceData['bvid']?.toString() ?? '';
        var cid = int.tryParse('${video.sourceData['cid']}') ?? 0;
        if (cid <= 0) {
          final detail = await _bilibili.getVideo(bvid);
          if (!_isCurrent(token, nextPlayer)) return null;
          cid = detail.parts.first.cid;
          video = video.copyWith(sourceData: {...video.sourceData, 'cid': cid});
        }
        final resolved = await _bilibili.resolvePlayback(bvid, cid,
            quality: playbackQuality.value);
        if (!_isCurrent(token, nextPlayer)) return null;
        resolvedBili = resolved;
        headers = resolved.headers;
        // mpv EDL joins split MP4 files into one seekable timeline.
        url = resolved.isDash
            ? resolved.videoUrl!
            : resolved.segments.length == 1
                ? resolved.segments.single
                : 'edl://${resolved.segments.map((segment) => '%${utf8.encode(segment).length}%$segment').join(';')}';
      } else if (_apiClient.isBackendUrl(url) && _apiClient.token != null) {
        headers = {'Authorization': 'Bearer ${_apiClient.token}'};
      }
      if (!_isCurrent(token, nextPlayer)) return null;
      activeVideo.value = video;
      if (resolvedBili != null) {
        playbackQuality.value = resolvedBili.quality;
        availableQualities.assignAll(resolvedBili.availableQualities);
      }
      _bindPlaybackProgress(nextPlayer, video, token);
      final media = Media(url, httpHeaders: headers);
      final externalAudio = cached?.audioPath ?? resolvedBili?.audioUrl;
      final hasExternalAudio = externalAudio != null;
      if (hasExternalAudio) {
        final target = nextPlayer;
        if (!await _waitForDashReady(target, token,
            command: () => target.open(media, play: false),
            ready: () => _hasVideoReady(target.state),
            phase: '视频')) {
          return null;
        }
        if (!_isCurrent(token, target)) return null;
        final audioUrl = externalAudio;
        if (!await _waitForDashReady(target, token,
            command: () => target.setAudioTrack(AudioTrack.uri(audioUrl)),
            ready: () => target.state.tracks.audio
                .any((track) => _isRealTrack(track.id)),
            phase: '音轨')) {
          return null;
        }
      } else {
        await nextPlayer.open(media, play: true);
      }
      if (!_isCurrent(token, nextPlayer)) return null;
      await nextPlayer.setRate(playbackRate.value);
      if (!_isCurrent(token, nextPlayer)) return null;
      if (hasExternalAudio) {
        await nextPlayer.play();
        if (!_isCurrent(token, nextPlayer)) return null;
      }
      await DeviceIntegrationService.setVideoPlaybackActive(true);
      if (!_isCurrent(token, nextPlayer)) return null;
      _nativeMediaReady = true;
      await DeviceIntegrationService.setAudioOnlyBackground(listenMode.value);
      if (!_isCurrent(token, nextPlayer)) return null;
      _mediaStateSubscriptions.addAll([
        nextPlayer.stream.playing
            .listen((_) => _publishMediaState(force: true)),
        nextPlayer.stream.buffering
            .listen((_) => _publishMediaState(force: true)),
        nextPlayer.stream.rate.listen((_) => _publishMediaState(force: true)),
        nextPlayer.stream.position.listen((_) => _publishMediaState()),
        nextPlayer.stream.duration
            .listen((_) => _publishMediaState(force: true)),
      ]);
      _publishMediaState(force: true);
      if (video.source == 'bilibili' && cached == null) {
        unawaited(_initializeBiliSidecars(
            video, nextPlayer, token, subtitleRequest, danmakuRequest));
      } else {
        unawaited(_initializeSidecars(
            video, nextPlayer, token, subtitleRequest, danmakuRequest));
      }
      return nextPlayer;
    } catch (e) {
      if (_isCurrent(token, nextPlayer)) {
        playbackError.value = '无法播放：$e';
        // Native disposal may be queued behind a timed-out media command.
        // Detach synchronously, but do not keep the loading UI awaiting it.
        unawaited(_disposeVideoControllers().catchError((Object _) {}));
      }
      return null;
    } finally {
      if (_isCurrent(token)) isVideoLoading.value = false;
    }
  }

  bool _isRealTrack(String id) => id.isNotEmpty && id != 'auto' && id != 'no';

  bool _hasVideoReady(PlayerState state) =>
      ((state.width ?? 0) > 0 && (state.height ?? 0) > 0) ||
      (state.tracks.video.any((track) => _isRealTrack(track.id)) &&
          state.duration > Duration.zero &&
          !state.buffering);

  Future<bool> _waitForDashReady(Player target, int token,
      {required Future<void> Function() command,
      required bool Function() ready,
      required String phase}) async {
    if (!_isCurrent(token, target)) return false;
    final result = Completer<bool>();
    var commandCompleted = false;
    void check([dynamic _]) {
      if (result.isCompleted) return;
      if (!_isCurrent(token, target)) {
        result.complete(false);
      } else if (commandCompleted && ready()) {
        result.complete(true);
      }
    }

    void fail(String message) {
      if (result.isCompleted) return;
      if (!_isCurrent(token, target)) {
        result.complete(false);
      } else {
        result.completeError(StateError(message));
      }
    }

    // open/audio-add acknowledge commands before native media loading finishes.
    // Listen first so synchronous state changes cannot be missed. Never use the
    // selected track alone: media_kit also updates it after failed audio-add.
    final subscriptions = <StreamSubscription<dynamic>>[
      target.stream.width.listen(check),
      target.stream.height.listen(check),
      target.stream.tracks.listen(check),
      target.stream.duration.listen(check),
      target.stream.buffering.listen(check),
      target.stream.error.listen((_) => fail('DASH $phase加载失败，请重试')),
      target.stream.log.listen((log) {
        if ((log.level == 'error' || log.level == 'fatal') &&
            log.text.contains('audio-add')) {
          fail('DASH 音轨加载失败，请重试');
        }
      }),
    ];
    final timer =
        Timer(_dashReadyTimeout, () => fail('DASH $phase加载超时，请检查网络后重试'));
    unawaited(_playbackCancelled.future.then((_) {
      if (!result.isCompleted) result.complete(false);
    }));
    // Handle late command errors even when stop/timeout has already won.
    unawaited(Future<void>.sync(command).then((_) {
      commandCompleted = true;
      check();
    }, onError: (Object _, StackTrace __) {
      fail('DASH $phase加载失败，请重试');
    }));
    try {
      return await result.future;
    } finally {
      timer.cancel();
      await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()));
    }
  }

  Future<void> _initializeBiliSidecars(Video video, Player activePlayer,
      int token, int subtitleRequest, int danmakuRequest) async {
    if (!_isCurrent(token, activePlayer)) return;
    final cid = int.tryParse('${video.sourceData['cid']}') ?? 0;
    await Future.wait([
      _loadBiliSubtitles(video, activePlayer, token, subtitleRequest),
      if (_isDanmakuCurrent(token, activePlayer, danmakuRequest))
        _loadBiliDanmaku(activePlayer, cid, token, danmakuRequest),
    ]);
  }

  Future<void> _loadBiliSubtitles(
      Video video, Player activePlayer, int token, int request) async {
    try {
      final bvid = video.sourceData['bvid']?.toString() ?? '';
      final cid = int.tryParse('${video.sourceData['cid']}') ?? 0;
      final tracks = await _bilibili.getSubtitles(bvid, cid);
      if (!_isCurrent(token, activePlayer)) return;
      biliSubtitles.assignAll(tracks);
      if (tracks.isNotEmpty &&
          _isSubtitleCurrent(token, activePlayer, request)) {
        _selectedBiliSubtitle = tracks.first;
        await _loadBiliSubtitle(activePlayer, tracks.first, token, request);
      }
    } catch (_) {
      // Subtitle availability is independent of the danmaku endpoint.
    }
  }

  Future<void> _loadBiliDanmaku(
      Player activePlayer, int cid, int token, int request) async {
    try {
      final text = await _bilibili.getDanmakuXml(cid);
      if (!_isDanmakuCurrent(token, activePlayer, request)) return;
      danmakuCues.assignAll(_assignDanmakuLanes(_parseXmlDanmaku(text)));
    } catch (_) {
      // Missing platform tracks must never prevent authorized video playback.
    }
  }

  Future<void> selectBiliSubtitle(BiliSubtitle subtitle, {int? token}) async {
    final expected = token ?? _playbackToken;
    final activePlayer = player;
    if (activePlayer == null || !_isCurrent(expected, activePlayer)) return;
    final request = ++_subtitleRequest;
    _selectedBiliSubtitle = subtitle;
    selectedSubtitleSidecar.value = null;
    subtitleCues.clear();
    if (!_isSubtitleCurrent(expected, activePlayer, request)) return;
    await _loadBiliSubtitle(activePlayer, subtitle, expected, request);
  }

  Future<void> _loadBiliSubtitle(Player activePlayer, BiliSubtitle subtitle,
      int token, int request) async {
    try {
      final cues = await _bilibili.getSubtitleBody(subtitle);
      if (!_isSubtitleCurrent(token, activePlayer, request)) return;
      subtitleCues.assignAll(cues.map((cue) => SubtitleCue(
          start: Duration(milliseconds: (cue.from * 1000).round()),
          end: Duration(milliseconds: (cue.to * 1000).round()),
          text: cue.content)));
      await activePlayer.setSubtitleTrack(SubtitleTrack.no());
    } catch (_) {
      // Sidecars are optional and must not replace the current playback error.
    }
  }

  Future<void> setPlaybackRate(double rate, {bool persist = true}) async {
    playbackRate.value = rate;
    await player?.setRate(rate);
    if (persist) await savePlaybackPreferences();
  }

  Future<void> savePlaybackPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('study_playback_rate', playbackRate.value);
    await prefs.setBool('study_auto_next', autoNext.value);
    await prefs.setInt('study_double_tap_seconds', doubleTapSeconds.value);
    await prefs.setDouble('study_long_press_rate', longPressRate.value);
  }

  Future<void> setPlaybackQuality(int quality) async {
    final video = activeVideo.value;
    if (video == null || video.source != 'bilibili') return;
    final position = player?.state.position.inSeconds ?? 0;
    final stopping = stopCurrentPlayback();
    final token = _playbackToken;
    await stopping;
    if (!_isCurrent(token)) return;
    playbackQuality.value = quality;
    await loadVideoDetail(video.id,
        initial: video.copyWith(sourceData: {
          ...video.sourceData,
          'position_seconds': position,
        }));
  }

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepMinutes.value = minutes;
    if (minutes <= 0) return;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      sleepMinutes.value = 0;
      unawaited(player?.pause());
    });
  }

  Future<void> downloadCurrent() async {
    final video = activeVideo.value;
    if (video == null) return;
    final cache = _mediaCache;
    final scope = cache.scopeKey;
    if (video.source == 'bilibili') {
      final playback = await _bilibili.resolvePlayback(
          '${video.sourceData['bvid']}',
          int.tryParse('${video.sourceData['cid']}') ?? 0,
          quality: playbackQuality.value);
      final attachments =
          await biliOfflineAttachments(_bilibili, video, warning: (message) {
        if (scope == cache.scopeKey) {
          cache.errors[cache.keyFor(video)] = message;
        }
      });
      if (scope != cache.scopeKey) throw StateError('账号已切换，请重试');
      await cache.downloadBundle(
          video,
          playback.isDash ? [playback.videoUrl!] : playback.segments,
          playback.headers,
          audioUrl: playback.audioUrl,
          attachments: attachments,
          representationId: 'quality:${playback.quality}',
          expectedScope: scope);
      return;
    }
    final url = _apiClient.absoluteUrl(video.videoUrl);
    if (scope != cache.scopeKey) throw StateError('账号已切换，请重试');
    await cache.download(video, url, const {});
  }

  Future<void> _initializeSidecars(Video video, Player activePlayer, int token,
      int subtitleRequest, int danmakuRequest) async {
    if (!_isCurrent(token, activePlayer)) return;
    videoSidecars.assignAll(video.sidecars);
    final subtitle = video.subtitleSidecars.firstOrNull;
    final danmaku = video.danmakuSidecars.firstOrNull;
    if (subtitleRequest == _subtitleRequest) {
      selectedSubtitleSidecar.value = subtitle;
      subtitleCues.clear();
    }
    if (danmakuRequest == _danmakuRequest) {
      selectedDanmakuSidecar.value = danmaku;
      danmakuCues.clear();
    }
    await Future.wait([
      if (subtitle != null &&
          _isSubtitleCurrent(token, activePlayer, subtitleRequest))
        _loadSubtitleSidecar(activePlayer, subtitle, token, subtitleRequest),
      if (!subtitlesEnabled.value) _disableNativeSubtitles(activePlayer, token),
      if (danmaku != null &&
          _isDanmakuCurrent(token, activePlayer, danmakuRequest))
        _loadDanmakuSidecar(activePlayer, danmaku, token, danmakuRequest),
    ]);
  }

  Future<void> _disableNativeSubtitles(Player activePlayer, int token) async {
    if (!_isCurrent(token, activePlayer)) return;
    try {
      await activePlayer.setSubtitleTrack(SubtitleTrack.no());
    } catch (_) {}
  }

  Future<void> _loadSubtitleSidecar(
    Player activePlayer,
    VideoSidecar sidecar,
    int token,
    int request,
  ) async {
    try {
      final text = await _readSidecar(sidecar);
      if (!_isSubtitleCurrent(token, activePlayer, request)) return;
      if (text.trim().isEmpty) return;
      final cues = _parseSubtitles(text, sidecar.extension);
      subtitleCues.assignAll(cues);
      if (cues.isNotEmpty) {
        await activePlayer.setSubtitleTrack(SubtitleTrack.no());
      } else {
        await activePlayer.setSubtitleTrack(
          SubtitleTrack.data(
            text,
            title: sidecar.title.isEmpty ? sidecar.fileName : sidecar.title,
          ),
        );
      }
    } catch (_) {
      // A failed or stale optional track must not affect current playback.
    }
  }

  Future<void> _loadDanmakuSidecar(
      Player activePlayer, VideoSidecar sidecar, int token, int request) async {
    try {
      final text = await _readSidecar(sidecar);
      if (!_isDanmakuCurrent(token, activePlayer, request)) return;
      final cues = _assignDanmakuLanes(_parseDanmaku(text, sidecar.extension));
      danmakuCues.assignAll(cues);
    } catch (_) {
      if (_isDanmakuCurrent(token, activePlayer, request)) danmakuCues.clear();
    }
  }

  Future<String> _readSidecar(VideoSidecar sidecar) async {
    if (Uri.tryParse(sidecar.url)?.scheme == 'file') {
      final video = activeVideo.value;
      if (video == null) throw StateError('没有当前视频');
      final text = await _mediaCache.readSidecar(video, sidecar);
      if (text == null) throw StateError('本机附件不属于此视频或已损坏');
      return text;
    }
    return _apiClient.getText(sidecar.url);
  }

  List<DanmakuCue> _parseDanmaku(String text, String extension) {
    final value = text.trim();
    if (value.isEmpty) return [];
    if (extension == '.json' ||
        value.startsWith('{') ||
        value.startsWith('[')) {
      final parsed = _parseJsonDanmaku(value);
      if (parsed.isNotEmpty) return parsed;
    }
    if (extension == '.ass' ||
        extension == '.ssa' ||
        value.contains('[Events]') ||
        value.contains('Dialogue:')) {
      final parsed = _parseAssDanmaku(value);
      if (parsed.isNotEmpty) return parsed;
    }
    return _parseXmlDanmaku(value);
  }

  List<SubtitleCue> _parseSubtitles(String text, String extension) {
    final value = text.trim();
    if (value.isEmpty) return [];
    if (extension == '.ass' ||
        extension == '.ssa' ||
        value.contains('[Events]') ||
        value.contains('Dialogue:')) {
      return _parseAssSubtitles(value);
    }
    return _parseSrtOrVttSubtitles(value);
  }

  List<SubtitleCue> _parseSrtOrVttSubtitles(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty);
    final cues = <SubtitleCue>[];
    final timePattern = RegExp(
      r'(?<start>\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3}|\d{1,2}:\d{2}[\.,]\d{1,3})\s*-->\s*(?<end>\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3}|\d{1,2}:\d{2}[\.,]\d{1,3})',
    );
    for (final block in blocks) {
      final lines = block.split('\n').map((line) => line.trim()).toList();
      final timeIndex = lines.indexWhere((line) => timePattern.hasMatch(line));
      if (timeIndex < 0) continue;
      final match = timePattern.firstMatch(lines[timeIndex]);
      if (match == null) continue;
      final start = _parseSubtitleTime(match.namedGroup('start'));
      final end = _parseSubtitleTime(match.namedGroup('end'));
      if (start == null || end == null || end.compareTo(start) <= 0) continue;
      final cueText = lines
          .skip(timeIndex + 1)
          .map(_cleanSubtitleText)
          .where((line) => line.isNotEmpty)
          .join('\n');
      if (cueText.isEmpty) continue;
      cues.add(SubtitleCue(start: start, end: end, text: cueText));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  List<SubtitleCue> _parseAssSubtitles(String text) {
    final events = _parseAssDialogueLines(text);
    return events
        .map((event) {
          final start = _parseAssTime(event.start);
          final end = _parseAssTime(event.end);
          final cueText = _cleanAssText(event.text);
          if (start == null ||
              end == null ||
              end.compareTo(start) <= 0 ||
              cueText.isEmpty) {
            return null;
          }
          return SubtitleCue(start: start, end: end, text: cueText);
        })
        .whereType<SubtitleCue>()
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  List<DanmakuCue> _parseAssDanmaku(String text) {
    final events = _parseAssDialogueLines(text);
    final cues = <DanmakuCue>[];
    for (final event in events) {
      final start = _parseAssTime(event.start);
      final cueText = _cleanAssText(event.text);
      if (start == null || cueText.isEmpty) continue;
      cues.add(
        DanmakuCue(
          start: start,
          text: cueText,
          color: _parseAssColor(event.text),
        ),
      );
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  List<DanmakuCue> _parseXmlDanmaku(String text) {
    final cues = <DanmakuCue>[];
    final pattern = RegExp(
      r'<d\b[^>]*\bp="([^"]+)"[^>]*>(.*?)</d>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in pattern.allMatches(text)) {
      final attrs = match.group(1)?.split(',') ?? const [];
      if (attrs.isEmpty) continue;
      final seconds = double.tryParse(attrs.first) ?? 0;
      final content = _decodeDanmakuText(match.group(2) ?? '');
      if (content.isEmpty) continue;
      cues.add(
        DanmakuCue(
          start: Duration(milliseconds: (seconds * 1000).round()),
          text: content,
          color: attrs.length > 3 ? int.tryParse(attrs[3]) : null,
        ),
      );
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  List<DanmakuCue> _parseJsonDanmaku(String text) {
    try {
      final decoded = jsonDecode(text);
      final list = decoded is List
          ? decoded
          : decoded is Map
              ? (decoded['data'] ??
                  decoded['comments'] ??
                  decoded['danmaku'] ??
                  decoded['items'])
              : null;
      if (list is! List) return [];
      final cues = <DanmakuCue>[];
      for (final item in list) {
        if (item is! Map) continue;
        final textValue = (item['text'] ??
                item['content'] ??
                item['message'] ??
                item['m'] ??
                '')
            .toString()
            .trim();
        if (textValue.isEmpty) continue;
        final milliseconds = _danmakuTimeToMilliseconds(
          item['time'] ?? item['start'] ?? item['at'] ?? item['progress'],
        );
        if (milliseconds == null) continue;
        cues.add(
          DanmakuCue(
            start: Duration(milliseconds: milliseconds),
            text: textValue,
            color: item['color'] is int
                ? item['color'] as int
                : int.tryParse(item['color']?.toString() ?? ''),
          ),
        );
      }
      cues.sort((a, b) => a.start.compareTo(b.start));
      return cues;
    } catch (_) {
      return [];
    }
  }

  List<DanmakuCue> _assignDanmakuLanes(List<DanmakuCue> cues) {
    if (cues.isEmpty) return cues;
    final sorted = [...cues]..sort((a, b) => a.start.compareTo(b.start));
    final laneAvailableAt = List<Duration>.filled(12, Duration.zero);
    final assigned = <DanmakuCue>[];
    for (final cue in sorted) {
      var lane = 0;
      for (var index = 0; index < laneAvailableAt.length; index++) {
        if (cue.start >= laneAvailableAt[index]) {
          lane = index;
          break;
        }
        if (laneAvailableAt[index] < laneAvailableAt[lane]) {
          lane = index;
        }
      }
      laneAvailableAt[lane] = cue.start + const Duration(milliseconds: 1400);
      assigned.add(
        DanmakuCue(
          start: cue.start,
          text: cue.text,
          color: cue.color,
          lane: lane,
        ),
      );
    }
    return assigned..sort((a, b) => a.start.compareTo(b.start));
  }

  List<_AssDialogue> _parseAssDialogueLines(String text) {
    final events = <_AssDialogue>[];
    var format = <String>[
      'layer',
      'start',
      'end',
      'style',
      'name',
      'marginl',
      'marginr',
      'marginv',
      'effect',
      'text',
    ];

    for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';')) continue;
      final lower = line.toLowerCase();
      if (lower.startsWith('format:')) {
        format = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((item) => item.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!lower.startsWith('dialogue:')) continue;

      final payload = line.substring(line.indexOf(':') + 1).trim();
      final parts = _splitAssCsv(payload, format.length);
      if (parts.length < format.length) continue;
      final startIndex = format.indexOf('start');
      final endIndex = format.indexOf('end');
      final textIndex = format.indexOf('text');
      if (startIndex < 0 || endIndex < 0 || textIndex < 0) continue;
      events.add(
        _AssDialogue(
          start: parts[startIndex].trim(),
          end: parts[endIndex].trim(),
          text: parts[textIndex].trim(),
        ),
      );
    }
    return events;
  }

  List<String> _splitAssCsv(String value, int fieldCount) {
    if (fieldCount <= 1) return [value];
    final parts = <String>[];
    var start = 0;
    for (var index = 0; index < fieldCount - 1; index++) {
      final comma = value.indexOf(',', start);
      if (comma < 0) break;
      parts.add(value.substring(start, comma));
      start = comma + 1;
    }
    parts.add(value.substring(start));
    return parts;
  }

  Duration? _parseSubtitleTime(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceAll(',', '.');
    final parts = normalized.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (seconds == null || minutes == null || hours == null) return null;
    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }

  Duration? _parseAssTime(String? value) {
    return _parseSubtitleTime(value);
  }

  String _cleanSubtitleText(String value) {
    return _decodeDanmakuText(value)
        .replaceAll(RegExp(r'\{.*?\}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanAssText(String value) {
    return _decodeDanmakuText(value
            .replaceAll(RegExp(r'\{[^}]*\}'), '')
            .replaceAll(r'\N', '\n')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\h', ' '))
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }

  int? _parseAssColor(String value) {
    final match = RegExp(r'\\(?:1?c|c)&H([0-9A-Fa-f]{6,8})&').firstMatch(value);
    if (match == null) return null;
    final raw = match.group(1);
    if (raw == null) return null;
    final bgr = raw.length > 6 ? raw.substring(raw.length - 6) : raw;
    if (bgr.length != 6) return null;
    final blue = int.tryParse(bgr.substring(0, 2), radix: 16);
    final green = int.tryParse(bgr.substring(2, 4), radix: 16);
    final red = int.tryParse(bgr.substring(4, 6), radix: 16);
    if (red == null || green == null || blue == null) return null;
    return (red << 16) | (green << 8) | blue;
  }

  int? _danmakuTimeToMilliseconds(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return value > 100000 ? value : value * 1000;
    }
    if (value is double) {
      return value > 100000 ? value.round() : (value * 1000).round();
    }
    final number = double.tryParse(value.toString());
    if (number == null) return null;
    return number > 100000 ? number.round() : (number * 1000).round();
  }

  String _decodeDanmakuText(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  Future<void> loadRelatedVideos(int videoId) async {
    try {
      final response = await _apiClient.get(
        '${ApiEndpoints.videos}/$videoId/related',
      );

      if (response.statusCode == 200) {
        final List<dynamic> data =
            response.data is List ? response.data : response.data['data'];
        relatedVideos.value = data.map((json) => Video.fromJson(json)).toList();
      }
    } catch (e) {
      print('加载相关视频失败: $e');
      // 使用模拟数据
      relatedVideos.value = _getMockVideos().take(3).toList();
    }
  }

  Future<void> filterByCategory(String category) async {
    if (category == '全部') {
      await filterByNasCategory(null);
      return;
    }

    final matched = categories.firstWhereOrNull(
      (item) => item.name == category || item.path == category,
    );
    if (matched != null) {
      await filterByNasCategory(matched);
      return;
    }

    selectedCategory.value = category;
    selectedCategoryId.value = null;
    videos.assignAll(allVideos.where((v) => v.category == category));
    filteredVideos.assignAll(videos);
    _applyCurrentSort();
  }

  Future<void> filterByNasCategory(VideoCategory? category) async {
    if (category == null) {
      selectedRootCategoryId.value = null;
      selectedCategory.value = '全部';
      selectedCategoryId.value = null;
      expandedCategoryIds.clear();
      _applyVideoFilters();
      return;
    }

    final root = rootForCategory(category) ?? category;
    final rootChanged = selectedRootCategoryId.value != root.id;
    selectedRootCategoryId.value = root.id;
    selectedCategory.value = category.path;
    selectedCategoryId.value = category.id;
    if (rootChanged || expandedCategoryIds.isEmpty) {
      _expandFirstBranch(root);
    }
    _expandAncestors(category);
    _applyVideoFilters();
  }

  Future<void> selectRootCategory(VideoCategory category) async {
    final rootChanged = selectedRootCategoryId.value != category.id;
    selectedRootCategoryId.value = category.id;
    selectedCategory.value = category.path;
    selectedCategoryId.value = category.id;
    if (rootChanged || expandedCategoryIds.isEmpty) {
      _expandFirstBranch(category);
    }
    _applyVideoFilters();
  }

  void toggleCategoryExpansion(VideoCategory category) {
    if (expandedCategoryIds.contains(category.id)) {
      expandedCategoryIds.remove(category.id);
    } else {
      expandedCategoryIds.add(category.id);
    }
    expandedCategoryIds.refresh();
  }

  List<VideoCategory> get rootCategories {
    return categories.where((category) {
      final parentId = category.parentId;
      return parentId == null ||
          parentId == 0 ||
          !categories.any((item) => item.id == parentId);
    }).toList();
  }

  VideoCategory? get selectedRootCategory {
    final rootId = selectedRootCategoryId.value;
    if (rootId == null) return null;
    return categories.firstWhereOrNull((category) => category.id == rootId);
  }

  List<VideoCategory> childrenOf(int parentId) {
    return categories
        .where((category) => category.parentId == parentId)
        .toList();
  }

  VideoCategory? rootForCategory(VideoCategory category) {
    return rootCategories.firstWhereOrNull((root) {
      return category.id == root.id ||
          category.path == root.path ||
          category.path.startsWith('${root.path}/');
    });
  }

  void _ensureRootSelection() {
    final roots = rootCategories;
    if (roots.isEmpty) {
      selectedRootCategoryId.value = null;
      selectedCategoryId.value = null;
      selectedCategory.value = '全部';
      expandedCategoryIds.clear();
      return;
    }

    final currentRootId = selectedRootCategoryId.value;
    final root =
        roots.firstWhereOrNull((category) => category.id == currentRootId) ??
            roots.first;
    final rootChanged = currentRootId != root.id;
    selectedRootCategoryId.value = root.id;

    final selectedId = selectedCategoryId.value;
    final selectedStillValid = selectedId != null &&
        categories.any((category) =>
            category.id == selectedId && _isUnderRoot(category, root));
    if (!selectedStillValid) {
      selectedCategoryId.value = root.id;
      selectedCategory.value = root.path;
    }

    if (rootChanged || expandedCategoryIds.isEmpty) {
      _expandFirstBranch(root);
    }
  }

  bool _isUnderRoot(VideoCategory category, VideoCategory root) {
    return category.id == root.id ||
        category.path == root.path ||
        category.path.startsWith('${root.path}/');
  }

  void _expandFirstBranch(VideoCategory root) {
    final expanded = <int>{};
    var children = childrenOf(root.id);
    while (children.isNotEmpty) {
      final first = children.first;
      if (childrenOf(first.id).isEmpty) break;
      expanded.add(first.id);
      children = childrenOf(first.id);
    }
    _replaceExpandedCategories(expanded);
  }

  void _expandAncestors(VideoCategory category) {
    final expanded = Set<int>.from(expandedCategoryIds);
    var parentId = category.parentId;
    while (parentId != null && parentId != 0) {
      final parent = categories.firstWhereOrNull((item) => item.id == parentId);
      if (parent == null) break;
      expanded.add(parent.id);
      parentId = parent.parentId;
    }
    _replaceExpandedCategories(expanded);
  }

  void _replaceExpandedCategories(Set<int> categoryIds) {
    expandedCategoryIds
      ..clear()
      ..addAll(categoryIds);
    expandedCategoryIds.refresh();
  }

  void sortVideos(String sortType) {
    sortBy.value = sortType;
    _applyVideoFilters();
  }

  void filterByWatchStatus(String status) {
    selectedWatchStatus.value = status;
    _applyVideoFilters();
  }

  void _applyVideoFilters() {
    final selectedId = selectedCategoryId.value;
    final selectedCategory = selectedId == null
        ? null
        : categories.firstWhereOrNull((category) => category.id == selectedId);
    var items = allVideos.where((video) {
      if (selectedCategory == null) return true;
      if (video.nasCategoryId == selectedCategory.id) return true;
      if (video.nasCategoryPath.isEmpty) return false;
      return video.nasCategoryPath == selectedCategory.path ||
          video.nasCategoryPath.startsWith('${selectedCategory.path}/');
    }).toList();

    switch (selectedWatchStatus.value) {
      case 'watched':
        items = items.where((video) => video.isWatched).toList();
        break;
      case 'watching':
        items = items.where((video) => video.isWatching).toList();
        break;
      case 'unwatched':
        items = items
            .where((video) => !video.isWatched && !video.isWatching)
            .toList();
        break;
    }

    videos.assignAll(items);
    filteredVideos.assignAll(items);
    _applyCurrentSort();
  }

  List<Video> videosForWatchStatus(String status) {
    final selectedId = selectedCategoryId.value;
    final selectedCategory = selectedId == null
        ? null
        : categories.firstWhereOrNull((category) => category.id == selectedId);
    return allVideos.where((video) {
      final inCategory = selectedCategory == null ||
          video.nasCategoryId == selectedCategory.id ||
          (video.nasCategoryPath.isNotEmpty &&
              (video.nasCategoryPath == selectedCategory.path ||
                  video.nasCategoryPath
                      .startsWith('${selectedCategory.path}/')));
      if (!inCategory) return false;
      if (status == 'watched') return video.isWatched;
      if (status == 'watching') return video.isWatching;
      return !video.isWatched && !video.isWatching;
    }).toList();
  }

  List<Video> courseVideosFor(Video video) {
    if (courseQueue.any((item) => item.id == video.id)) {
      return courseQueue.toList();
    }
    if (video.source == 'bilibili') return [video];
    final path = video.nasCategoryPath.trim();
    final category = video.category.trim();
    var items = allVideos.where((item) {
      if (path.isNotEmpty) {
        return item.nasCategoryPath == path;
      }
      if (category.isNotEmpty) {
        return item.category == category;
      }
      return item.id == video.id;
    }).toList();

    if (items.isEmpty) {
      items = [video];
    }
    items.sort(_compareVideosByEpisode);
    return items;
  }

  void _applyCurrentSort() {
    switch (sortBy.value) {
      case 'episode':
        filteredVideos.sort(_compareVideosByEpisode);
        break;
      case 'newest':
        filteredVideos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'popular':
        // 假设有观看次数字段
        filteredVideos.sort((a, b) => b.id.compareTo(a.id));
        break;
      case 'duration':
        filteredVideos.sort((a, b) => a.duration.compareTo(b.duration));
        break;
    }
  }

  int _compareVideosByEpisode(Video a, Video b) {
    final sortCompare =
        _effectiveSortOrder(a).compareTo(_effectiveSortOrder(b));
    if (sortCompare != 0) return sortCompare;
    final episodeCompare = (_effectiveEpisodeNumber(a) ?? 2147483647)
        .compareTo(_effectiveEpisodeNumber(b) ?? 2147483647);
    if (episodeCompare != 0) return episodeCompare;
    return a.title.compareTo(b.title);
  }

  int _effectiveSortOrder(Video video) {
    if (video.sortOrder > 0) return video.sortOrder;
    return _effectiveEpisodeNumber(video) ?? 2147483647;
  }

  int? _effectiveEpisodeNumber(Video video) {
    if (video.episodeNumber != null && video.episodeNumber! > 0) {
      return video.episodeNumber;
    }
    return _chapterNumberFromTitle(video.title);
  }

  int? _chapterNumberFromTitle(String value) {
    final match = RegExp(
      r'第\s*([0-9]+|[零〇一二两三四五六七八九十百千万亿]+)\s*[章节集讲课篇]',
    ).firstMatch(value);
    if (match == null) return null;
    final raw = match.group(1) ?? '';
    final arabic = int.tryParse(raw);
    return arabic ?? _chineseNumberToInt(raw);
  }

  int? _chineseNumberToInt(String value) {
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const units = <String, int>{
      '十': 10,
      '百': 100,
      '千': 1000,
      '万': 10000,
      '亿': 100000000,
    };
    if (value.isEmpty ||
        value.runes.any((rune) {
          final char = String.fromCharCode(rune);
          return !digits.containsKey(char) && !units.containsKey(char);
        })) {
      return null;
    }
    if (value.runes
        .every((rune) => digits.containsKey(String.fromCharCode(rune)))) {
      return int.tryParse(
        value.runes
            .map((rune) => '${digits[String.fromCharCode(rune)]}')
            .join(),
      );
    }

    var total = 0;
    var section = 0;
    var number = 0;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final digit = digits[char];
      if (digit != null) {
        number = digit;
        continue;
      }
      final unit = units[char]!;
      if (unit >= 10000) {
        section = (section + number) * unit;
        total += section;
        section = 0;
        number = 0;
      } else {
        if (number == 0) number = 1;
        section += number * unit;
        number = 0;
      }
    }
    return total + section + number;
  }

  void _bindPlaybackProgress(Player activePlayer, Video video, int token) {
    final resumePercent = video.progressPercent;
    final exactPosition =
        int.tryParse('${video.sourceData['position_seconds']}') ?? 0;
    _durationSubscription = activePlayer.stream.duration.listen((duration) {
      if (!_isCurrent(token, activePlayer)) return;
      if (_resumeApplied ||
          (resumePercent <= 0 && exactPosition <= 0) ||
          (video.isWatched && exactPosition <= 0) ||
          duration.inMilliseconds <= 0) {
        return;
      }
      _resumeApplied = true;
      final target = Duration(
        milliseconds: (exactPosition > 0
                ? exactPosition * 1000
                : (duration.inMilliseconds * (resumePercent / 100)).round())
            .clamp(0, duration.inMilliseconds),
      );
      activePlayer.seek(target);
    });

    _positionSubscription = activePlayer.stream.position.listen((position) {
      if (!_isCurrent(token, activePlayer)) return;
      final duration = activePlayer.state.duration;
      if (duration.inMilliseconds <= 0) return;
      final end = repeatEnd.value;
      if (repeatStart.value != null && end != null && position >= end) {
        unawaited(activePlayer.seek(repeatStart.value!));
        return;
      }
      final percent = (position.inMilliseconds / duration.inMilliseconds * 100)
          .clamp(0, 100)
          .toDouble();
      _updateLocalVideoProgress(video.id, percent, percent >= 95);

      final now = DateTime.now();
      if (_lastProgressSyncAt != null &&
          now.difference(_lastProgressSyncAt!).inSeconds < 10) {
        return;
      }
      _lastProgressSyncAt = now;
      saveVideoProgress(video.id, percent, completed: percent >= 95);
    });

    _completedSubscription = activePlayer.stream.completed.listen((completed) {
      if (!completed || !_isCurrent(token, activePlayer)) return;
      _updateLocalVideoProgress(video.id, 100, true);
      unawaited(saveVideoProgress(video.id, 100, completed: true));
      unawaited(Future<void>(() async {
        if (!autoNext.value || !_isCurrent(token, activePlayer)) return;
        final queue = courseVideosFor(video);
        final index = queue.indexWhere((item) => item.id == video.id);
        if (index >= 0 && index + 1 < queue.length) {
          await loadVideoDetail(queue[index + 1].id, initial: queue[index + 1]);
        }
      }));
    });
  }

  void _mergeVideo(Video video) {
    void replaceIn(RxList<Video> target) {
      final index = target.indexWhere((item) => item.id == video.id);
      if (index >= 0) target[index] = video;
    }

    replaceIn(allVideos);
    replaceIn(videos);
    replaceIn(filteredVideos);
  }

  void _updateLocalVideoProgress(
    int videoId,
    double progressPercent,
    bool completed,
  ) {
    final cleanPercent = progressPercent.clamp(0, 100).toDouble();
    Video update(Video video) {
      return video.copyWith(
        progressPercent: cleanPercent,
        completed: completed,
      );
    }

    for (final target in [allVideos, videos, filteredVideos, relatedVideos]) {
      final index = target.indexWhere((video) => video.id == videoId);
      if (index >= 0) target[index] = update(target[index]);
    }
  }

  Future<void> saveVideoProgress(
    int videoId,
    double progressPercent, {
    bool completed = false,
  }) async {
    try {
      final current = activeVideo.value;
      if (current?.id != videoId) return;
      final duration =
          player?.state.duration.inSeconds ?? current!.duration.inSeconds;
      final position =
          completed ? duration : player?.state.position.inSeconds ?? 0;
      await StudyProgressSync.instance.save(
        itemId: current!.studyItemId,
        videoId: videoId > 0 ? videoId : null,
        duration: duration,
        position: position.clamp(0, duration > 0 ? duration : position),
        completed: completed,
      );
    } catch (e) {
      print('保存视频进度失败: $e');
    }
  }

  void toggleFavorite(Video video) {
    if (video.studyItemId != null) {
      final next = !(activeVideo.value?.isFavorite ?? video.isFavorite);
      _apiClient.put('/study/items/${video.studyItemId}',
          data: {'favorite': next}).then((_) {
        activeVideo.value = video.copyWith(isFavorite: next);
      });
      return;
    }
    final index = videos.indexWhere((v) => v.id == video.id);
    if (index != -1) {
      videos[index] = video.copyWith(isFavorite: !video.isFavorite);

      // 更新筛选列表
      final filteredIndex = filteredVideos.indexWhere((v) => v.id == video.id);
      if (filteredIndex != -1) {
        filteredVideos[filteredIndex] = videos[index];
      }

      // 调用API更新收藏状态
      _updateFavoriteStatus(video.id, videos[index].isFavorite);
    }
  }

  Future<void> _updateFavoriteStatus(int videoId, bool isFavorite) async {
    try {
      if (isFavorite) {
        await _apiClient.post(
          ApiEndpoints.addFavorite,
          data: {'video_id': videoId},
        );
      } else {
        await _apiClient.delete(
          '${ApiEndpoints.removeFavorite}/video/$videoId',
        );
      }
    } catch (e) {
      print('更新收藏状态失败: $e');
    }
  }

  List<Video> _getMockVideos() {
    return [
      Video(
        id: 1,
        title: '假设检验基础',
        description: '学习假设检验的基本概念和步骤，包括原假设、备择假设、检验统计量等',
        category: '基础统计',
        thumbnailUrl: '',
        videoUrl: '',
        duration: const Duration(minutes: 15),
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        tags: ['假设检验', 'P值', '显著性水平'],
      ),
      Video(
        id: 2,
        title: '生存分析入门',
        description: '了解生存分析的基本概念，包括生存函数、风险函数、Kaplan-Meier方法',
        category: '生存分析',
        thumbnailUrl: '',
        videoUrl: '',
        duration: const Duration(minutes: 20),
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        tags: ['生存分析', 'Kaplan-Meier', 'Cox回归'],
      ),
      Video(
        id: 3,
        title: '临床试验设计概述',
        description: '介绍临床试验的基本设计类型，包括随机对照试验、交叉设计等',
        category: '临床试验',
        thumbnailUrl: '',
        videoUrl: '',
        duration: const Duration(minutes: 25),
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        tags: ['临床试验', 'RCT', '随机化'],
      ),
      Video(
        id: 4,
        title: '线性回归分析',
        description: '讲解线性回归的原理、假设检验和模型诊断',
        category: '回归分析',
        thumbnailUrl: '',
        videoUrl: '',
        duration: const Duration(minutes: 30),
        createdAt: DateTime.now().subtract(const Duration(days: 4)),
        tags: ['线性回归', '最小二乘法', 'R²'],
      ),
      Video(
        id: 5,
        title: '样本量计算方法',
        description: '介绍不同研究设计下的样本量计算方法和功效分析',
        category: '样本量计算',
        thumbnailUrl: '',
        videoUrl: '',
        duration: const Duration(minutes: 18),
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        tags: ['样本量', '功效分析', '效应量'],
      ),
    ];
  }
}
