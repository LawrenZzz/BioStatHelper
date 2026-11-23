import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/study_controller.dart';
import 'study_home_view.dart';

class VideoListView extends StatefulWidget {
  const VideoListView({super.key});
  @override
  State<VideoListView> createState() => _VideoListViewState();
}

class _VideoListViewState extends State<VideoListView>
    with WidgetsBindingObserver {
  late final StudyController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = !Get.isRegistered<StudyController>();
    _controller = _ownsController
        ? Get.put(StudyController())
        : Get.find<StudyController>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_controller.isClosed) {
      unawaited(_controller.refreshAll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController &&
        Get.isRegistered<StudyController>() &&
        identical(Get.find<StudyController>(), _controller)) {
      if (_controller.focusStarted.value != null) {
        unawaited(_controller.finishFocus(completed: false));
      }
      Get.delete<StudyController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StudyHomeView(controller: _controller);
}
