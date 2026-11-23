import 'package:get/get.dart';
import '../modules/auth/views/login_view.dart';
import '../modules/auth/bindings/auth_binding.dart';
import '../modules/shell/views/shell_view.dart';
import '../modules/shell/bindings/shell_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/video/views/video_list_view.dart';
import '../modules/video/views/video_player_view.dart';
import '../modules/video/bindings/video_binding.dart';
import '../modules/concepts/views/concepts_view.dart';
import '../modules/concepts/views/concept_detail_view.dart';
import '../modules/concepts/bindings/concepts_binding.dart';
import '../modules/reference/views/reference_view.dart';
import '../modules/reference/bindings/reference_binding.dart';
import '../modules/projects/views/projects_view.dart';
import '../modules/projects/views/project_detail_view.dart';
import '../modules/projects/bindings/projects_binding.dart';
import '../modules/settings/views/settings_view.dart';
import '../modules/settings/bindings/settings_binding.dart';
import '../modules/today/views/today_view.dart';
import '../modules/today/bindings/today_binding.dart';
import 'app_routes.dart';

class AppPages {
  static const initial = AppRoutes.shell;

  static final routes = [
    GetPage(
      name: AppRoutes.login,
      page: () => const LoginView(),
      binding: AuthBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.shell,
      page: () => const ShellView(),
      binding: ShellBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.videoList,
      page: () => const VideoListView(),
      binding: VideoBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.videoPlayer,
      page: () => const VideoPlayerView(),
      binding: VideoBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.concepts,
      page: () => const ConceptsView(),
      binding: ConceptsBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.conceptDetail,
      page: () => const ConceptDetailView(),
      binding: ConceptsBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.reference,
      page: () => const ReferenceView(),
      binding: ReferenceBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.projects,
      page: () => const ProjectsView(),
      binding: ProjectsBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.projectDetail,
      page: () => const ProjectDetailView(),
      binding: ProjectsBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.settings,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.today,
      page: () => const TodayView(),
      binding: TodayBinding(),
      transition: Transition.rightToLeft,
    ),
  ];
}
