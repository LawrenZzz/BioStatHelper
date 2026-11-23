class AppConstants {
  // 应用信息
  static const String appName = '生统助手';
  static const String appVersion = '0.1.67';
  static const String appDescription = '专为生物统计师设计的学习与资源查阅工具';

  // 存储键名
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String themeKey = 'theme_mode';
  static const String themeSeedKey = 'theme_seed';
  static const String dynamicColorKey = 'use_dynamic_color';
  static const String amoledDarkKey = 'amoled_dark';
  static const String languageKey = 'language';
  static const String firstLaunchKey = 'first_launch';

  // 视频分类
  static const List<Map<String, dynamic>> videoCategories = [
    {'id': 1, 'name': '基础统计', 'icon': '📊', 'description': '统计学基础知识'},
    {'id': 2, 'name': '临床试验', 'icon': '🏥', 'description': '临床试验设计与分析'},
    {'id': 3, 'name': '生存分析', 'icon': '📈', 'description': '生存分析方法'},
    {'id': 4, 'name': '回归分析', 'icon': '📉', 'description': '回归模型与应用'},
    {'id': 5, 'name': '贝叶斯统计', 'icon': '🎯', 'description': '贝叶斯方法'},
    {'id': 6, 'name': '样本量计算', 'icon': '🔢', 'description': '样本量与功效分析'},
    {'id': 7, 'name': '多重比较', 'icon': '🔄', 'description': '多重检验校正'},
    {'id': 8, 'name': '缺失数据', 'icon': '❓', 'description': '缺失数据处理'},
    {'id': 9, 'name': '统计软件', 'icon': '💻', 'description': 'R、SAS、Python等'},
    {'id': 10, 'name': '监管指南', 'icon': '📋', 'description': 'ICH、FDA指南'},
  ];

  // 概念分类
  static const List<Map<String, dynamic>> conceptCategories = [
    {'id': 1, 'name': '假设检验', 'icon': '🔬', 'description': '假设检验基础'},
    {'id': 2, 'name': '置信区间', 'icon': '📏', 'description': '置信区间估计'},
    {'id': 3, 'name': 'P值', 'icon': '🎯', 'description': 'P值解释与应用'},
    {'id': 4, 'name': '效应量', 'icon': '📐', 'description': '效应量度量'},
    {'id': 5, 'name': '功效分析', 'icon': '⚡', 'description': '统计功效'},
    {'id': 6, 'name': '多重比较', 'icon': '🔄', 'description': '多重检验'},
    {'id': 7, 'name': '模型诊断', 'icon': '🔍', 'description': '模型假设检验'},
    {'id': 8, 'name': '数据转换', 'icon': '🔀', 'description': '数据变换方法'},
  ];

  // 快速参考分类
  static const List<Map<String, dynamic>> referenceCategories = [
    {'id': 1, 'name': '常用公式', 'icon': '📐', 'description': '统计公式速查'},
    {'id': 2, 'name': '临界值表', 'icon': '📊', 'description': 't、z、F、χ²分布表'},
    {'id': 3, 'name': '样本量表', 'icon': '🔢', 'description': '样本量速查'},
    {'id': 4, 'name': '检验清单', 'icon': '✅', 'description': '分析前检查清单'},
    {'id': 5, 'name': '报告模板', 'icon': '📝', 'description': '统计报告模板'},
    {'id': 6, 'name': 'ICH指南', 'icon': '📋', 'description': 'ICH E9等指南摘要'},
  ];

  // 学习路径
  static const List<Map<String, dynamic>> learningPaths = [
    {
      'id': 'beginner',
      'name': '入门路径',
      'description': '适合统计学初学者',
      'icon': '🌱',
      'steps': [
        '基础统计概念',
        '描述性统计',
        '假设检验基础',
        't检验与方差分析',
        '相关与回归基础',
      ],
    },
    {
      'id': 'intermediate',
      'name': '进阶路径',
      'description': '适合有一定基础的统计师',
      'icon': '🌿',
      'steps': [
        '多元回归分析',
        '生存分析基础',
        '临床试验设计',
        '样本量计算',
        '多重比较方法',
      ],
    },
    {
      'id': 'advanced',
      'name': '高级路径',
      'description': '适合资深统计师',
      'icon': '🌳',
      'steps': [
        '贝叶斯统计',
        '自适应设计',
        '缺失数据处理',
        '复杂生存模型',
        '机器学习应用',
      ],
    },
  ];
}
