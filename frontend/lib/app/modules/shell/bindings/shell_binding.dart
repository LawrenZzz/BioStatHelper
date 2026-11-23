import 'package:get/get.dart';

import '../../home/controllers/home_controller.dart';
import '../../projects/controllers/projects_controller.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../today/controllers/today_controller.dart';
import '../../video/controllers/video_controller.dart';
import '../controllers/shell_controller.dart';

class ShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ShellController>(() => ShellController());
    if (!Get.isRegistered<HomeController>()) {
      Get.lazyPut<HomeController>(() => HomeController());
    }
    if (!Get.isRegistered<ProjectsController>()) {
      Get.lazyPut<ProjectsController>(() => ProjectsController());
    }
    if (!Get.isRegistered<VideoController>()) {
      Get.lazyPut<VideoController>(() => VideoController());
    }
    if (!Get.isRegistered<SettingsController>()) {
      Get.lazyPut<SettingsController>(() => SettingsController());
    }
    if (!Get.isRegistered<TodayController>()) {
      Get.lazyPut<TodayController>(() => TodayController());
    }
  }
}
