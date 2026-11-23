class AppConfig {
  // API配置
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  // 应用信息
  static const String appName = '生统助手';
  static const String appVersion = '0.1.67';
  static const String appDescription = '专为生物统计师设计的学习与资源查阅工具';

  // 视频配置
  static const String videoBaseUrl = String.fromEnvironment(
    'VIDEO_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1/admin/nas-videos',
  );

  // 缓存配置
  static const int cacheExpirationHours = 24;

  // 分页配置
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // 视频播放配置
  static const bool autoPlay = true;
  static const bool showControls = true;
  static const bool looping = false;

  // 学习配置
  static const int defaultDailyGoalMinutes = 30;
  static const int minDailyGoalMinutes = 15;
  static const int maxDailyGoalMinutes = 120;
}
