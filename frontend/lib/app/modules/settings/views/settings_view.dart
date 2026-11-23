import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/values/app_config.dart';
import '../../../theme/app_theme.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: Obx(() {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildProfileSection(context),
            const SizedBox(height: 24),
            _buildAppearanceSection(context),
            const SizedBox(height: 24),
            _buildLearningSection(context),
            const SizedBox(height: 24),
            _buildDataSection(context),
            const SizedBox(height: 24),
            _buildAboutSection(context),
            const SizedBox(height: 100),
          ],
        );
      }),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '个人资料',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Obx(() {
              final user = controller.authService.user.value;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                title: Text(user?.username ?? '未登录'),
                subtitle: Text(user?.email ?? '登录后同步学习数据'),
              );
            }),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              subtitle: const Text('清除本机登录状态'),
              onTap: controller.logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '外观',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'system',
                  label: Text('跟随系统'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: 'light',
                  label: Text('浅色'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text('深色'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {controller.themeMode.value},
              onSelectionChanged: (values) {
                controller.updateThemeMode(values.first);
              },
            ),
            const SizedBox(height: 18),
            Text(
              '主题颜色',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppTheme.themeSeeds.map((seed) {
                return _ThemeSeedButton(
                  seed: seed,
                  selected: controller.themeSeed.value == seed.id &&
                      !controller.useDynamicColor.value,
                  onTap: () => controller.updateThemeSeed(seed.id),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.palette_outlined),
              title: const Text('系统动态取色'),
              subtitle: const Text('Android 12+ 使用系统强调色'),
              value: controller.useDynamicColor.value,
              onChanged: controller.toggleDynamicColor,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.contrast_outlined),
              title: const Text('AMOLED 黑色背景'),
              subtitle: const Text('深色模式下使用纯黑背景'),
              value: controller.amoledDark.value,
              onChanged: controller.toggleAmoledDark,
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('字体大小'),
              subtitle: Text('${controller.fontSize.value.toInt()}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showFontSizeDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '学习设置',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('学习提醒'),
              subtitle: Text(
                controller.learningReminder.value ? '已启用' : '已禁用',
              ),
              trailing: Switch(
                value: controller.learningReminder.value,
                onChanged: (value) {
                  controller.toggleLearningReminder(value);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('每日学习目标'),
              subtitle: Text('${controller.dailyGoal.value} 分钟'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showDailyGoalDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.school),
              title: const Text('学习路径'),
              subtitle: Text(
                  _learningPathName(controller.preferredLearningPath.value)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showLearningPathDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '数据管理',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('离线数据'),
              subtitle: const Text('管理离线下载的内容'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showInfoDialog(
                  context,
                  '离线数据',
                  '当前版本会保留必要的本地设置和缓存。视频文件仍从后端或 NAS 读取，离线下载入口已预留。',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('同步设置'),
              subtitle: Text(
                controller.autoSync.value ? '自动同步已启用' : '手动同步',
              ),
              trailing: Switch(
                value: controller.autoSync.value,
                onChanged: (value) {
                  controller.toggleAutoSync(value);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('清除缓存'),
              subtitle: const Text('清除本地缓存数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showClearCacheDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '关于',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('版本'),
              subtitle: Text('v${AppConfig.appVersion}'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('使用条款'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showInfoDialog(context, '使用条款', '请仅将本工具用于学习、资料整理和合规的内部工作流。');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: const Text('隐私政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showInfoDialog(context, '隐私政策', '账号、设置、收藏和学习进度保存在你部署的后端数据库中。');
              },
            ),
            ListTile(
              leading: const Icon(Icons.feedback),
              title: const Text('意见反馈'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showInfoDialog(context, '意见反馈', '请在你的项目维护渠道记录问题，后续可接入后端反馈表。');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return LiquidGlassAlertDialog(
          title: const Text('字体大小'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '当前字体大小: ${controller.fontSize.value.toInt()}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Slider(
                value: controller.fontSize.value,
                min: 12,
                max: 24,
                divisions: 12,
                label: controller.fontSize.value.toInt().toString(),
                onChanged: (value) {
                  controller.updateFontSize(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showDailyGoalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return LiquidGlassAlertDialog(
          title: const Text('每日学习目标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '当前目标: ${controller.dailyGoal.value} 分钟',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Slider(
                value: controller.dailyGoal.value.toDouble(),
                min: 15,
                max: 120,
                divisions: 7,
                label: '${controller.dailyGoal.value} 分钟',
                onChanged: (value) {
                  controller.updateDailyGoal(value.toInt());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showLearningPathDialog(BuildContext context) {
    final paths = {
      'beginner': '入门路径',
      'intermediate': '进阶路径',
      'advanced': '高级路径',
    };

    showDialog(
      context: context,
      builder: (context) {
        return LiquidGlassAlertDialog(
          title: const Text('学习路径'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: paths.entries.map((entry) {
              return RadioListTile<String>(
                title: Text(entry.value),
                value: entry.key,
                groupValue: controller.preferredLearningPath.value,
                onChanged: (value) {
                  if (value != null) {
                    controller.updateLearningPath(value);
                    Navigator.pop(context);
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return LiquidGlassAlertDialog(
          title: const Text('清除缓存'),
          content: const Text('确定要清除所有本地缓存数据吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                controller.clearCache();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('缓存已清除'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return LiquidGlassAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  String _learningPathName(String value) {
    switch (value) {
      case 'intermediate':
        return '进阶路径';
      case 'advanced':
        return '高级路径';
      case 'beginner':
      default:
        return '入门路径';
    }
  }
}

class _ThemeSeedButton extends StatelessWidget {
  const _ThemeSeedButton({
    required this.seed,
    required this.selected,
    required this.onTap,
  });

  final AppThemeSeed seed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: seed.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 84,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  selected ? colorScheme.primary : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.42)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: seed.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: ThemeData.estimateBrightnessForColor(seed.color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                seed.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
