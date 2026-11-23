import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'core/services/auth_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/study_background.dart' as study_background;

@pragma('vm:entry-point')
Future<void> studyBackgroundMain() => study_background.studyBackgroundMain();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  MediaKit.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await Get.putAsync(() => ThemeService().init(), permanent: true);
  await Get.putAsync(() => AuthService().init());
  runApp(const BioStatHelperApp());
}

class BioStatHelperApp extends StatelessWidget {
  const BioStatHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();
    return Obx(
      () => GetMaterialApp(
        title: '生统助手',
        debugShowCheckedModeBanner: false,
        theme: themeService.lightTheme,
        darkTheme: themeService.darkTheme,
        themeMode: themeService.themeMode,
        initialRoute: Get.find<AuthService>().isAuthenticated.value
            ? AppPages.initial
            : AppRoutes.login,
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
        locale: const Locale('zh', 'CN'),
        fallbackLocale: const Locale('en', 'US'),
      ),
    );
  }
}
