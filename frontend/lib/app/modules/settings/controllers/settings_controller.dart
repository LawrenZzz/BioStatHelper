import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/theme_service.dart';
import '../../../../core/values/api_endpoints.dart';

class SettingsController extends GetxController {
  final ApiClient _apiClient = ApiClient();
  final AuthService authService = Get.find<AuthService>();
  final ThemeService themeService = Get.find<ThemeService>();

  // 可观察变量
  late final RxString themeMode = themeService.themeModeValue;
  late final RxString themeSeed = themeService.themeSeed;
  late final RxBool useDynamicColor = themeService.useDynamicColor;
  late final RxBool amoledDark = themeService.amoledDark;
  final fontSize = 16.0.obs;
  final learningReminder = true.obs;
  final dailyGoal = 30.obs;
  final autoSync = true.obs;
  final preferredLearningPath = 'beginner'.obs;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      fontSize.value = prefs.getDouble('fontSize') ?? 16.0;
      learningReminder.value = prefs.getBool('learningReminder') ?? true;
      dailyGoal.value = prefs.getInt('dailyGoal') ?? 30;
      autoSync.value = prefs.getBool('autoSync') ?? true;
      preferredLearningPath.value =
          prefs.getString('preferredLearningPath') ?? 'beginner';
      await loadRemoteSettings();
    } catch (e) {
      print('加载设置失败: $e');
    }
  }

  Future<void> loadRemoteSettings() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.settings);
      final data = response.data;
      await themeService.applySettings(
        themeMode: data['theme_mode'],
        seed: data['theme_seed'],
        dynamicColor: data['use_dynamic_color'],
        amoled: data['amoled_dark'],
      );
      fontSize.value = (data['font_size'] ?? 16.0).toDouble();
      learningReminder.value = data['learning_reminder'] ?? true;
      dailyGoal.value = data['daily_goal_minutes'] ?? 30;
      autoSync.value = data['auto_sync'] ?? true;
      preferredLearningPath.value =
          data['preferred_learning_path'] ?? 'beginner';
      await _saveLocalSettings();
    } catch (e) {
      print('加载远程设置失败: $e');
    }
  }

  Future<void> _saveLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', fontSize.value);
    await prefs.setBool('learningReminder', learningReminder.value);
    await prefs.setInt('dailyGoal', dailyGoal.value);
    await prefs.setBool('autoSync', autoSync.value);
    await prefs.setString('preferredLearningPath', preferredLearningPath.value);
  }

  Future<void> _syncRemoteSettings() async {
    try {
      await _apiClient.put(
        ApiEndpoints.settings,
        data: {
          'theme_mode': themeMode.value,
          'theme_seed': themeSeed.value,
          'use_dynamic_color': useDynamicColor.value,
          'amoled_dark': amoledDark.value,
          'font_size': fontSize.value,
          'learning_reminder': learningReminder.value,
          'daily_goal_minutes': dailyGoal.value,
          'auto_sync': autoSync.value,
          'preferred_learning_path': preferredLearningPath.value,
        },
      );
    } catch (e) {
      print('同步远程设置失败: $e');
    }
  }

  Future<void> toggleDarkMode(bool value) async {
    await updateThemeMode(value ? 'dark' : 'light');
  }

  Future<void> updateThemeMode(String value) async {
    try {
      await themeService.updateThemeMode(value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存主题模式失败: $e');
    }
  }

  Future<void> updateThemeSeed(String value) async {
    try {
      await themeService.updateThemeSeed(value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存主题颜色失败: $e');
    }
  }

  Future<void> toggleDynamicColor(bool value) async {
    try {
      await themeService.toggleDynamicColor(value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存动态取色设置失败: $e');
    }
  }

  Future<void> toggleAmoledDark(bool value) async {
    try {
      await themeService.toggleAmoledDark(value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存AMOLED设置失败: $e');
    }
  }

  Future<void> updateFontSize(double value) async {
    fontSize.value = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('fontSize', value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存字体大小设置失败: $e');
    }
  }

  Future<void> toggleLearningReminder(bool value) async {
    learningReminder.value = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('learningReminder', value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存学习提醒设置失败: $e');
    }
  }

  Future<void> updateDailyGoal(int value) async {
    dailyGoal.value = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('dailyGoal', value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存每日目标设置失败: $e');
    }
  }

  Future<void> toggleAutoSync(bool value) async {
    autoSync.value = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('autoSync', value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存自动同步设置失败: $e');
    }
  }

  Future<void> updateLearningPath(String value) async {
    preferredLearningPath.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preferredLearningPath', value);
      await _syncRemoteSettings();
    } catch (e) {
      print('保存学习路径失败: $e');
    }
  }

  Future<void> logout() async {
    await authService.logout();
  }

  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await themeService.applySettings(
        themeMode: 'system',
        seed: 'biostat',
        dynamicColor: false,
        amoled: false,
      );

      // 重新加载默认设置
      await loadSettings();
    } catch (e) {
      print('清除缓存失败: $e');
    }
  }
}
