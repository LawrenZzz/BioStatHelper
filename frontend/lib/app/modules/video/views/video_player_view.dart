import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mpv;
import '../controllers/video_controller.dart';
import '../controllers/study_controller.dart';
import '../../../../core/services/device_integration_service.dart';
import '../../../../shared/models/video_model.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';
import '../../../../shared/widgets/video_thumbnail_preview.dart';
import 'study_player_tools.dart';
import 'study_settings_view.dart';
import '../../../../core/services/study_preferences.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  final VideoController controller = Get.find<VideoController>();
  late Video video;
  bool _allowPop = false;
  bool _stoppedForPop = false;
  bool _showPlayerControls = false;
  bool _isFullscreen = false;
  Timer? _controlsTimer;
  Offset? _gestureStart;
  Offset _gestureDelta = Offset.zero;
  String? _gestureMode;
  String? _gestureLabel;
  Duration? _gestureStartPosition;
  Duration? _gestureSeekPosition;
  double _brightness = 1;
  double _volume = 0.5;
  double _gestureStartBrightness = 0.5;
  double _gestureStartVolume = 0.5;
  double? _rateBeforeHold;
  Worker? _activeVideoWorker;
  StudyPreferencesController? _studyPreferences;
  Worker? _layoutWorker;

  bool get _usesAndroidSystemControls =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _supportsFloatingPlayback =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    video = Get.arguments as Video;
    if (Get.isRegistered<StudyController>()) {
      _studyPreferences = Get.find<StudyController>().preferences;
      _studyPreferences!.addListener(_applyStudyPreferences);
      _applyStudyPreferences();
    }
    _layoutWorker = ever(controller.preferredLayout, (_) {
      if (mounted && !_isFullscreen) unawaited(_applyOrientation());
    });
    _activeVideoWorker = ever(controller.activeVideo, (Video? active) {
      if (active != null && mounted) setState(() => video = active);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.loadVideoDetail(video.id, initial: video);
      unawaited(_loadGestureLevels());
      unawaited(_applyOrientation());
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _activeVideoWorker?.dispose();
    _layoutWorker?.dispose();
    _studyPreferences?.removeListener(_applyStudyPreferences);
    unawaited(_restoreSystemUi());
    if (_isWindows && controller.isPictureInPicture.value) {
      unawaited(controller.exitFloatingPlayback());
    }
    if (!_stoppedForPop) {
      controller.stopCurrentPlayback();
    }
    super.dispose();
  }

  void _applyStudyPreferences() {
    final preferences = _studyPreferences;
    if (preferences?.isLoaded == true) {
      controller.applyStudyPreferences(preferences!.savedValue);
    }
  }

  Future<void> _applyOrientation() async {
    if (!_usesAndroidSystemControls) return;
    final layout = controller.preferredLayout.value;
    await SystemChrome.setPreferredOrientations(layout == 'portrait'
        ? [DeviceOrientation.portraitUp]
        : layout == 'landscape'
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight
              ]
            : DeviceOrientation.values);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final inPip = controller.isPictureInPicture.value;
      final windowsFloating = inPip && _isWindows;
      final playerOnly = inPip || _isFullscreen;
      return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (windowsFloating) {
            await _exitWindowsFloatingPlayback();
            return;
          }
          if (_isFullscreen) {
            await _setFullscreen(false);
            return;
          }
          await _stopPlaybackForPop();
          if (!context.mounted) return;
          setState(() => _allowPop = true);
          Navigator.of(context).pop(result);
        },
        child: Scaffold(
          backgroundColor: playerOnly ? Colors.black : null,
          appBar: playerOnly
              ? null
              : AppBar(
                  title: Text(video.title),
                  actions: [
                    if (_supportsFloatingPlayback)
                      IconButton(
                        tooltip: '悬浮播放',
                        icon: const Icon(Icons.picture_in_picture_alt),
                        onPressed: _enterFloatingPlayback,
                      ),
                    if (_usesAndroidSystemControls)
                      IconButton(
                        tooltip: '悬浮权限',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: controller.requestFloatingPlaybackPermission,
                      ),
                    IconButton(
                      icon: Icon(
                        video.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: video.isFavorite ? Colors.red : null,
                      ),
                      onPressed: () {
                        controller.toggleFavorite(video);
                      },
                    ),
                  ],
                ),
          body: playerOnly
              ? ColoredBox(
                  color: Colors.black,
                  child: Center(child: _buildVideoPlayer(context, video)),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final useTabletLayout = constraints.maxWidth >= 840 &&
                        controller.preferredLayout.value != 'portrait';
                    if (!useTabletLayout) {
                      return _buildPhoneLayout(context);
                    }
                    return _buildTabletLayout(context);
                  },
                ),
        ),
      );
    });
  }

  Widget _buildPhoneLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVideoPlayer(context, video),
          _buildVideoInfo(context, video),
          _buildRelatedVideos(context),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 360,
            child: _buildCourseSidebar(context),
          ),
          VerticalDivider(
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildVideoPlayer(context, video),
                  _buildVideoInfo(context, video),
                  _buildRelatedVideos(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _stopPlaybackForPop() async {
    if (_stoppedForPop) return;
    _stoppedForPop = true;
    await controller.stopCurrentPlayback();
  }

  void _playVideo(Video nextVideo) {
    if (nextVideo.id == video.id) return;
    setState(() {
      video = nextVideo;
      _stoppedForPop = false;
    });
    controller.loadVideoDetail(nextVideo.id, initial: nextVideo);
  }

  Widget _buildCourseSidebar(BuildContext context) {
    return Obx(() {
      final courseVideos = controller.courseVideosFor(video);
      final courseTitle = video.nasCategoryPath.isNotEmpty
          ? video.nasCategoryPath.split('/').last
          : (video.category.isNotEmpty ? video.category : '当前课程');
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '课程目录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    courseTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                itemCount: courseVideos.length,
                itemBuilder: (context, index) {
                  final item = courseVideos[index];
                  return _CourseVideoTile(
                    video: item,
                    index: index,
                    selected: item.id == video.id,
                    onTap: () => _playVideo(item),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildVideoPlayer(BuildContext context, Video video) {
    return Obx(() {
      if (controller.isVideoLoading.value) {
        return Container(
          height: 220,
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      }

      if (controller.mediaVideoController == null ||
          controller.playbackError.value.isNotEmpty) {
        return Container(
          height: 220,
          color: Colors.black,
          child: Center(
            child: Text(
              controller.playbackError.value.isNotEmpty
                  ? controller.playbackError.value
                  : '视频加载失败',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }

      final inPip = controller.isPictureInPicture.value;
      final windowsFloating = inPip && _isWindows;
      final playerSurface = LayoutBuilder(
        builder: (context, constraints) {
          return MouseRegion(
            cursor:
                windowsFloating ? SystemMouseCursors.move : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: inPip && !windowsFloating ? null : _togglePlayerControls,
              onDoubleTapDown: inPip
                  ? null
                  : (details) {
                      unawaited(controller.handleDoubleTap(
                          x: details.localPosition.dx / constraints.maxWidth,
                          y: details.localPosition.dy / constraints.maxHeight));
                    },
              onLongPressStart: inPip
                  ? null
                  : (_) {
                      _rateBeforeHold = controller.playbackRate.value;
                      unawaited(controller.setPlaybackRate(
                          controller.longPressRate.value,
                          persist: false));
                    },
              onLongPressEnd: inPip
                  ? null
                  : (_) {
                      unawaited(controller.setPlaybackRate(_rateBeforeHold ?? 1,
                          persist: false));
                      _rateBeforeHold = null;
                    },
              onPanStart: windowsFloating
                  ? (_) => unawaited(
                        DeviceIntegrationService.startFloatingWindowDrag(),
                      )
                  : inPip
                      ? null
                      : _startPlayerGesture,
              onPanUpdate: inPip
                  ? null
                  : (details) => _updatePlayerGesture(details, constraints),
              onPanEnd: inPip ? null : _endPlayerGesture,
              onPanCancel: inPip ? null : _cancelPlayerGesture,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!controller.listenMode.value)
                    mpv.Video(
                      controller: controller.mediaVideoController!,
                      controls: null,
                      subtitleViewConfiguration: mpv.SubtitleViewConfiguration(
                        visible: controller.subtitlesEnabled.value &&
                            controller.subtitleCues.isEmpty,
                        padding: EdgeInsets.fromLTRB(
                          inPip ? 8 : 14,
                          0,
                          inPip ? 8 : 14,
                          inPip ? 8 : 18,
                        ),
                        style: TextStyle(
                          height: 1.35,
                          fontSize: inPip ? 13 : 28,
                          letterSpacing: 0,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 3),
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  if (controller.listenMode.value)
                    const Center(
                        child: Icon(Icons.headphones,
                            color: Colors.white70, size: 56)),
                  if (!_usesAndroidSystemControls && _brightness < 0.99)
                    IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: ((1 - _brightness) * 0.72).clamp(0, 0.72),
                        ),
                      ),
                    ),
                  if (!inPip) _buildDanmakuOverlay(context),
                  _buildSubtitleOverlay(context, compact: inPip),
                  if (!inPip && _showPlayerControls)
                    _buildPlayerControlsOverlay(context),
                  if (windowsFloating && _showPlayerControls)
                    _buildWindowsFloatingControls(context),
                  if (!inPip) _buildGestureIndicator(context),
                ],
              ),
            ),
          );
        },
      );

      if (_isFullscreen) {
        return SizedBox.expand(child: playerSurface);
      }

      return AspectRatio(
        aspectRatio: 16 / 9,
        child: playerSurface,
      );
    });
  }

  Future<void> _setFullscreen(bool value) async {
    if (!mounted || _isFullscreen == value) return;
    setState(() {
      _isFullscreen = value;
      _showPlayerControls = value;
    });
    _controlsTimer?.cancel();
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _scheduleControlsHide();
    } else {
      await _restoreSystemUi();
      await _applyOrientation();
    }
  }

  Future<void> _enterFloatingPlayback() async {
    if (_isFullscreen) {
      await _setFullscreen(false);
    }
    if (!mounted) return;
    setState(() => _showPlayerControls = false);
    await controller.enterFloatingPlayback();
  }

  Future<void> _exitWindowsFloatingPlayback() async {
    await controller.exitFloatingPlayback();
    if (!mounted) return;
    _controlsTimer?.cancel();
    setState(() => _showPlayerControls = false);
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _loadGestureLevels() async {
    final brightness = await DeviceIntegrationService.getPlaybackBrightness();
    final volume = await DeviceIntegrationService.getPlaybackVolume();
    if (!mounted) return;
    setState(() {
      _brightness = brightness ?? _brightness;
      _volume = volume ??
          ((controller.player?.state.volume ?? (_volume * 100)) / 100)
              .clamp(0, 1)
              .toDouble();
    });
  }

  void _startPlayerGesture(DragStartDetails details) {
    final position = controller.player?.state.position ?? Duration.zero;
    _controlsTimer?.cancel();
    setState(() {
      _gestureStart = details.localPosition;
      _gestureDelta = Offset.zero;
      _gestureMode = null;
      _gestureLabel = null;
      _gestureStartPosition = position;
      _gestureSeekPosition = position;
      _gestureStartBrightness = _brightness;
      _gestureStartVolume = _volume;
    });
  }

  void _updatePlayerGesture(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    final start = _gestureStart;
    if (start == null) return;
    final nextDelta = _gestureDelta + details.delta;
    final mode = _gestureMode ??
        (nextDelta.dx.abs() >= nextDelta.dy.abs()
            ? 'seek'
            : start.dx <= constraints.maxWidth / 2
                ? 'brightness'
                : 'volume');
    setState(() {
      _gestureDelta = nextDelta;
      _gestureMode = mode;
    });
    if (mode == 'seek') {
      _updateSeekGesture(nextDelta, constraints);
      return;
    }
    if (mode == 'brightness') {
      unawaited(_updateBrightnessGesture(nextDelta, constraints));
    } else {
      unawaited(_updateVolumeGesture(nextDelta, constraints));
    }
  }

  void _updateSeekGesture(Offset delta, BoxConstraints constraints) {
    final player = controller.player;
    final duration = player?.state.duration ?? Duration.zero;
    final start = _gestureStartPosition ?? Duration.zero;
    if (duration.inMilliseconds <= 0) {
      setState(() => _gestureLabel = '00:00');
      return;
    }
    final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
    final seekMilliseconds =
        (delta.dx / width * duration.inMilliseconds * 0.55).round();
    final target = Duration(
      milliseconds: (start.inMilliseconds + seekMilliseconds)
          .clamp(0, duration.inMilliseconds),
    );
    setState(() {
      _gestureSeekPosition = target;
      _gestureLabel =
          '${seekMilliseconds >= 0 ? '+' : '-'}${_formatDuration(Duration(milliseconds: seekMilliseconds.abs()))}'
          '  ${_formatDuration(target)}';
    });
  }

  Future<void> _updateBrightnessGesture(
    Offset delta,
    BoxConstraints constraints,
  ) async {
    final height = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
    final value =
        (_gestureStartBrightness - delta.dy / height).clamp(0.02, 1).toDouble();
    setState(() {
      _brightness = value;
      _gestureLabel = '亮度 ${(value * 100).round()}%';
    });
    await DeviceIntegrationService.setPlaybackBrightness(value);
  }

  Future<void> _updateVolumeGesture(
    Offset delta,
    BoxConstraints constraints,
  ) async {
    final height = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
    final value =
        (_gestureStartVolume - delta.dy / height).clamp(0, 1).toDouble();
    setState(() {
      _volume = value;
      _gestureLabel = '音量 ${(value * 100).round()}%';
    });
    final applied = await DeviceIntegrationService.setPlaybackVolume(value);
    if (applied == null) {
      await controller.player?.setVolume(value * 100);
    }
  }

  Future<void> _endPlayerGesture(DragEndDetails details) async {
    if (_gestureMode == 'seek' && _gestureSeekPosition != null) {
      await controller.player?.seek(_gestureSeekPosition!);
    }
    _clearGestureStateSoon();
    _scheduleControlsHide();
  }

  void _cancelPlayerGesture() {
    _clearGestureStateSoon();
    _scheduleControlsHide();
  }

  void _clearGestureStateSoon() {
    Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _gestureStart = null;
        _gestureDelta = Offset.zero;
        _gestureMode = null;
        _gestureLabel = null;
        _gestureStartPosition = null;
        _gestureSeekPosition = null;
      });
    });
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (_showPlayerControls) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showPlayerControls = false);
      });
    }
  }

  Widget _buildGestureIndicator(BuildContext context) {
    final label = _gestureLabel;
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    final icon = _gestureMode == 'seek'
        ? Icons.fast_forward
        : _gestureMode == 'brightness'
            ? Icons.brightness_6
            : Icons.volume_up;
    return Center(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _togglePlayerControls() {
    setState(() => _showPlayerControls = !_showPlayerControls);
    _scheduleControlsHide();
  }

  Widget _buildPlayerControlsOverlay(BuildContext context) {
    final player = controller.player;
    final hasSubtitles =
        controller.videoSidecars.any((item) => item.kind == 'subtitle') ||
            controller.biliSubtitles.isNotEmpty;
    final hasDanmaku =
        controller.videoSidecars.any((item) => item.kind == 'danmaku') ||
            controller.danmakuCues.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.45),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: 4, right: 4, child: _buildPlaybackMenu(context)),
          Center(
            child: StreamBuilder<bool>(
              stream: player?.stream.playing,
              initialData: player?.state.playing ?? false,
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return IconButton.filled(
                  iconSize: 36,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    unawaited(controller.togglePlayback());
                    _scheduleControlsHide();
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                );
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 6,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProgressSlider(context, player),
                  IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        fixedSize: const Size(36, 36),
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: _isFullscreen ? '退出全屏' : '全屏',
                          color: Colors.white,
                          onPressed: () =>
                              unawaited(_setFullscreen(!_isFullscreen)),
                          icon: Icon(
                            _isFullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                        ),
                        if (_supportsFloatingPlayback)
                          IconButton(
                            tooltip: '悬浮播放',
                            color: Colors.white,
                            onPressed: _enterFloatingPlayback,
                            icon: const Icon(Icons.picture_in_picture_alt),
                          ),
                        IconButton(
                          tooltip: controller.subtitlesEnabled.value
                              ? '关闭字幕'
                              : '打开字幕',
                          color: Colors.white,
                          onPressed: hasSubtitles
                              ? () {
                                  unawaited(
                                    controller.setSubtitlesEnabled(
                                      !controller.subtitlesEnabled.value,
                                    ),
                                  );
                                  _scheduleControlsHide();
                                }
                              : null,
                          icon: Icon(
                            controller.subtitlesEnabled.value
                                ? Icons.subtitles
                                : Icons.subtitles_off,
                          ),
                        ),
                        IconButton(
                          tooltip:
                              controller.danmakuEnabled.value ? '关闭弹幕' : '打开弹幕',
                          color: controller.danmakuEnabled.value
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.58),
                          onPressed: hasDanmaku
                              ? () {
                                  controller.setDanmakuEnabled(
                                    !controller.danmakuEnabled.value,
                                  );
                                  _scheduleControlsHide();
                                }
                              : null,
                          icon: Icon(
                            controller.danmakuEnabled.value
                                ? Icons.forum
                                : Icons.comments_disabled_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: '弹幕设置',
                          color: Colors.white,
                          onPressed: hasDanmaku
                              ? () => _showDanmakuSettings(context)
                              : null,
                          icon: const Icon(Icons.tune),
                        ),
                        const Spacer(),
                        Flexible(
                          child: StreamBuilder<Duration>(
                            stream: player?.stream.position,
                            initialData:
                                player?.state.position ?? Duration.zero,
                            builder: (context, snapshot) {
                              final position = snapshot.data ?? Duration.zero;
                              final duration =
                                  player?.state.duration ?? Duration.zero;
                              return Text(
                                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSlider(BuildContext context, Player? player) {
    return StreamBuilder<Duration>(
      stream: player?.stream.position,
      initialData: player?.state.position ?? Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player?.state.duration ?? Duration.zero;
        final max = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            min: 0,
            max: max,
            value: value,
            activeColor: Colors.white,
            inactiveColor: Colors.white.withValues(alpha: 0.28),
            onChanged: player == null
                ? null
                : (nextValue) {
                    unawaited(
                      player.seek(
                        Duration(milliseconds: nextValue.round()),
                      ),
                    );
                    _scheduleControlsHide();
                  },
          ),
        );
      },
    );
  }

  void _showDanmakuSettings(BuildContext context) {
    _controlsTimer?.cancel();
    showLiquidGlassBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Obx(
                  () => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '弹幕设置',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildDanmakuSettingSlider(
                          context: context,
                          icon: Icons.opacity,
                          label:
                              '透明度 ${(controller.danmakuOpacity.value * 100).round()}%',
                          value: controller.danmakuOpacity.value,
                          min: 0.15,
                          max: 1,
                          divisions: 17,
                          onChanged: controller.setDanmakuOpacity,
                        ),
                        _buildDanmakuSettingSlider(
                          context: context,
                          icon: Icons.vertical_align_center,
                          label:
                              '显示区域 ${(controller.danmakuAreaRatio.value * 100).round()}%',
                          value: controller.danmakuAreaRatio.value,
                          min: 0.2,
                          max: 1,
                          divisions: 16,
                          onChanged: controller.setDanmakuAreaRatio,
                        ),
                        _buildDanmakuSettingSlider(
                          context: context,
                          icon: Icons.format_size,
                          label:
                              '弹幕大小 ${controller.danmakuFontSize.value.round()}',
                          value: controller.danmakuFontSize.value,
                          min: 10,
                          max: 28,
                          divisions: 18,
                          onChanged: controller.setDanmakuFontSize,
                        ),
                        _buildDanmakuSettingSlider(
                          context: context,
                          icon: Icons.speed,
                          label:
                              '弹幕速度 ${controller.danmakuSpeed.value.toStringAsFixed(1)}x',
                          value: controller.danmakuSpeed.value,
                          min: 0.5,
                          max: 2,
                          divisions: 15,
                          onChanged: controller.setDanmakuSpeed,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(_scheduleControlsHide);
  }

  Widget _buildDanmakuSettingSlider({
    required BuildContext context,
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: (_) => unawaited(controller.saveDanmakuSettings()),
          ),
        ],
      ),
    );
  }

  Widget _buildDanmakuOverlay(BuildContext context) {
    final player = controller.player;
    return Obx(() {
      if (!controller.danmakuEnabled.value || controller.danmakuCues.isEmpty) {
        return const SizedBox.shrink();
      }
      return StreamBuilder<Duration>(
        stream: player?.stream.position,
        initialData: player?.state.position ?? Duration.zero,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          return LayoutBuilder(
            builder: (context, constraints) {
              final fontSize = controller.danmakuFontSize.value;
              final laneHeight = fontSize + 13;
              final travelDurationMilliseconds =
                  (6500 / controller.danmakuSpeed.value)
                      .round()
                      .clamp(3250, 13000);
              final maxLanes = (constraints.maxHeight *
                      controller.danmakuAreaRatio.value /
                      laneHeight)
                  .floor()
                  .clamp(1, 12);
              final active = controller.danmakuCues
                  .where((cue) {
                    final delta =
                        position.inMilliseconds - cue.start.inMilliseconds;
                    return delta >= 0 &&
                        delta <= travelDurationMilliseconds &&
                        cue.lane < maxLanes;
                  })
                  .take(24)
                  .toList();
              if (active.isEmpty) return const SizedBox.shrink();
              return Stack(
                children: [
                  for (var index = 0; index < active.length; index++)
                    _DanmakuText(
                      cue: active[index],
                      top: 12 + active[index].lane * laneHeight,
                      width: constraints.maxWidth,
                      progress: ((position.inMilliseconds -
                                  active[index].start.inMilliseconds) /
                              travelDurationMilliseconds)
                          .clamp(0, 1)
                          .toDouble(),
                      opacity: controller.danmakuOpacity.value,
                      fontSize: fontSize,
                    ),
                ],
              );
            },
          );
        },
      );
    });
  }

  Widget _buildSubtitleOverlay(
    BuildContext context, {
    required bool compact,
  }) {
    final player = controller.player;
    return Obx(() {
      if (!controller.subtitlesEnabled.value ||
          controller.subtitleCues.isEmpty) {
        return const SizedBox.shrink();
      }
      return StreamBuilder<Duration>(
        stream: player?.stream.position,
        initialData: player?.state.position ?? Duration.zero,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final active = controller.subtitleCues
              .where((cue) =>
                  cue.start.compareTo(position) <= 0 &&
                  cue.end.compareTo(position) >= 0)
              .toList();
          if (active.isEmpty) return const SizedBox.shrink();
          final text = active.map((cue) => cue.text).join('\n');
          return Positioned(
            left: compact ? 8 : 16,
            right: compact ? 8 : 16,
            bottom: compact ? 8 : (_showPlayerControls ? 62 : 18),
            child: IgnorePointer(
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(compact ? 5 : 8),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 6 : 10,
                      vertical: compact ? 3 : 6,
                    ),
                    child: Text(
                      text,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 13 : 17,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 2),
                          Shadow(color: Colors.black, blurRadius: 5),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildWindowsFloatingControls(BuildContext context) {
    final player = controller.player;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.32),
      child: Stack(
        children: [
          Center(
            child: StreamBuilder<bool>(
              stream: player?.stream.playing,
              initialData: player?.state.playing ?? false,
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return IconButton.filled(
                  tooltip: playing ? '暂停' : '播放',
                  iconSize: 34,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.52),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    unawaited(controller.togglePlayback());
                    _scheduleControlsHide();
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                );
              },
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: '返回应用',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.52),
                foregroundColor: Colors.white,
              ),
              onPressed: _exitWindowsFloatingPlayback,
              icon: const Icon(Icons.open_in_full),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildVideoInfo(BuildContext context, Video video) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  video.category,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.access_time,
                size: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                video.formattedDuration,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            video.description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (video.tags.isNotEmpty) ...[
            Text(
              '标签',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: video.tags.map((tag) {
                return Chip(
                  label: Text(tag),
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                );
              }).toList(),
            ),
          ],
          _buildSidecarSection(context),
          const SizedBox(height: 24),
          _buildActionButtons(context, video),
        ],
      ),
    );
  }

  Widget _buildSidecarSection(BuildContext context) {
    return Obx(() {
      final subtitles =
          controller.videoSidecars.where((item) => item.kind == 'subtitle');
      final danmaku =
          controller.videoSidecars.where((item) => item.kind == 'danmaku');
      if (subtitles.isEmpty && danmaku.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (subtitles.isNotEmpty)
              FilterChip(
                selected: controller.subtitlesEnabled.value,
                avatar: Icon(
                  controller.subtitlesEnabled.value
                      ? Icons.subtitles
                      : Icons.subtitles_off,
                  size: 18,
                ),
                label: Text('字幕 ${subtitles.length}'),
                onSelected: controller.setSubtitlesEnabled,
              ),
            if (danmaku.isNotEmpty)
              FilterChip(
                selected: controller.danmakuEnabled.value,
                avatar: Icon(
                  controller.danmakuEnabled.value
                      ? Icons.forum
                      : Icons.comments_disabled_outlined,
                  size: 18,
                ),
                label: Text('弹幕 ${danmaku.length}'),
                onSelected: controller.setDanmakuEnabled,
              ),
            if (subtitles.length > 1)
              ActionChip(
                avatar: const Icon(Icons.closed_caption_outlined, size: 18),
                label: Text(
                  controller.selectedSubtitleSidecar.value?.title ?? '选择字幕',
                ),
                onPressed: () => _showSidecarPicker(
                  context,
                  title: '选择字幕',
                  items: subtitles.toList(),
                  selected: controller.selectedSubtitleSidecar.value,
                  onSelected: controller.selectSubtitleSidecar,
                ),
              ),
            if (danmaku.length > 1)
              ActionChip(
                avatar: const Icon(Icons.forum_outlined, size: 18),
                label: Text(
                  controller.selectedDanmakuSidecar.value?.title ?? '选择弹幕',
                ),
                onPressed: () => _showSidecarPicker(
                  context,
                  title: '选择弹幕',
                  items: danmaku.toList(),
                  selected: controller.selectedDanmakuSidecar.value,
                  onSelected: controller.selectDanmakuSidecar,
                ),
              ),
          ],
        ),
      );
    });
  }

  void _showSidecarPicker(
    BuildContext context, {
    required String title,
    required List<VideoSidecar> items,
    required VideoSidecar? selected,
    required Future<void> Function(VideoSidecar?) onSelected,
  }) {
    showLiquidGlassBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final item in items)
                ListTile(
                  selected: selected?.id == item.id,
                  title: Text(item.title.isEmpty ? item.fileName : item.title),
                  subtitle: Text(item.fileName),
                  trailing: selected?.id == item.id
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await onSelected(item);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context, Video video) {
    return StudyPlayerTools(player: controller);
  }

  Widget _buildPlaybackMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '播放设置',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (value) async {
        if (value == 'settings' && Get.isRegistered<StudyController>()) {
          final study = Get.find<StudyController>();
          await Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => StudySettingsView(
                      controller: study.preferences,
                      scheduler: study.scheduler)));
          return;
        }
        if (value.startsWith('rate:')) {
          await controller.setPlaybackRate(double.parse(value.split(':').last));
        }
        if (value.startsWith('quality:')) {
          await controller.setPlaybackQuality(int.parse(value.split(':').last));
        }
        if (value.startsWith('sleep:')) {
          controller.setSleepTimer(int.parse(value.split(':').last));
        }
        if (value == 'next') controller.autoNext.toggle();
        if (value == 'listen') {
          await controller.setListenMode(!controller.listenMode.value);
        }
        if (value.startsWith('double:')) {
          controller.doubleTapSeconds.value = int.parse(value.split(':').last);
        }
        if (value.startsWith('hold:')) {
          controller.longPressRate.value = double.parse(value.split(':').last);
        }
        if (value == 'a') {
          controller.repeatStart.value = controller.player?.state.position;
        }
        if (value == 'b') {
          final position = controller.player?.state.position;
          if (position != null &&
              controller.repeatStart.value != null &&
              position > controller.repeatStart.value!) {
            controller.repeatEnd.value = position;
          }
        }
        if (value == 'clear') {
          controller.repeatStart.value = null;
          controller.repeatEnd.value = null;
        }
        if (value.startsWith('sub:')) {
          await controller.selectBiliSubtitle(
              controller.biliSubtitles[int.parse(value.split(':').last)]);
        }
        await controller.savePlaybackPreferences();
        _scheduleControlsHide();
      },
      itemBuilder: (_) => [
        if (Get.isRegistered<StudyController>())
          const PopupMenuItem(value: 'settings', child: Text('手势、布局与学习设置')),
        for (final rate in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
          CheckedPopupMenuItem(
              value: 'rate:$rate',
              checked: controller.playbackRate.value == rate,
              child: Text('${rate}x')),
        const PopupMenuDivider(),
        if (!Get.isRegistered<StudyController>()) ...[
          for (final seconds in [5, 10, 15, 30])
            CheckedPopupMenuItem(
                value: 'double:$seconds',
                checked: controller.doubleTapSeconds.value == seconds,
                child: Text('双击跳转 $seconds 秒')),
          for (final rate in [1.5, 2.0, 3.0])
            CheckedPopupMenuItem(
                value: 'hold:$rate',
                checked: controller.longPressRate.value == rate,
                child: Text('长按 ${rate}x')),
        ],
        const PopupMenuDivider(),
        for (final quality in controller.availableQualities)
          CheckedPopupMenuItem(
              value: 'quality:$quality',
              checked: controller.playbackQuality.value == quality,
              child: Text('画质 $quality')),
        for (var index = 0; index < controller.biliSubtitles.length; index++)
          PopupMenuItem(
              value: 'sub:$index',
              child: Text(controller.biliSubtitles[index].label)),
        CheckedPopupMenuItem(
            value: 'next',
            checked: controller.autoNext.value,
            child: const Text('自动连播')),
        CheckedPopupMenuItem(
            value: 'listen',
            checked: controller.listenMode.value,
            child: const Text('听课模式')),
        for (final minutes in [0, 15, 30, 60])
          CheckedPopupMenuItem(
              value: 'sleep:$minutes',
              checked: controller.sleepMinutes.value == minutes,
              child: Text(minutes == 0 ? '关闭定时暂停' : '$minutes 分钟后暂停')),
        const PopupMenuItem(value: 'a', child: Text('设为循环起点 A')),
        const PopupMenuItem(value: 'b', child: Text('设为循环终点 B')),
        const PopupMenuItem(value: 'clear', child: Text('清除 A–B 循环')),
      ],
    );
  }

  Widget _buildRelatedVideos(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '接下来学习',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              for (final next in controller.relatedVideos)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                        width: 96,
                        height: 54,
                        child: VideoThumbnailPreview(
                            video: next, height: 54, borderRadius: 6)),
                    title: Text(next.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(next.formattedDuration),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () => _playVideo(next)),
            ],
          ),
        ));
  }
}

class _DanmakuText extends StatelessWidget {
  const _DanmakuText({
    required this.cue,
    required this.top,
    required this.width,
    required this.progress,
    required this.opacity,
    required this.fontSize,
  });

  final DanmakuCue cue;
  final double top;
  final double width;
  final double progress;
  final double opacity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        cue.color == null ? Colors.white : Color(0xFF000000 | cue.color!);
    final color = baseColor.withValues(alpha: opacity.clamp(0.15, 1));
    final textStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      shadows: const [
        Shadow(color: Colors.black, blurRadius: 2),
        Shadow(color: Colors.black, blurRadius: 5),
      ],
    );
    final textPainter = TextPainter(
      text: TextSpan(text: cue.text, style: textStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    final left = width - progress * (width + textPainter.width + 24);
    return Positioned(
      top: top,
      left: left,
      child: IgnorePointer(
        child: Text(
          cue.text,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: textStyle,
        ),
      ),
    );
  }
}

class _CourseVideoTile extends StatelessWidget {
  const _CourseVideoTile({
    required this.video,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final Video video;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = video.isWatched
        ? colorScheme.onSurface.withValues(alpha: 0.52)
        : colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  height: 70,
                  child: VideoThumbnailPreview(
                    video: video,
                    height: 70,
                    width: 112,
                    borderRadius: 8,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.episodeNumber == null
                            ? '第${index + 1}课'
                            : '第${video.episodeNumber}集',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: textColor,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              decoration: video.isWatched
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                      ),
                      if (video.isWatching) ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: (video.progressPercent / 100)
                                .clamp(0, 1)
                                .toDouble(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
