import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/widgets/biostat_logo.dart';
import '../controllers/auth_controller.dart';

class LoginView extends GetView<AuthController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Obx(() {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Center(
                          child: BiostatLogo(size: 56),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '生统助手',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          controller.isRegisterMode.value
                              ? '创建账号后开始同步学习数据'
                              : '登录以同步学习进度和个人设置',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.62),
                                  ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: controller.usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '用户名或邮箱',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        if (controller.isRegisterMode.value) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: controller.emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '邮箱',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: controller.passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => controller.submit(),
                          decoration: const InputDecoration(
                            labelText: '密码',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed:
                              controller.isLoading ? null : controller.submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          icon: controller.isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : Icon(controller.isRegisterMode.value
                                  ? Icons.person_add_alt_1
                                  : Icons.login),
                          label: Text(
                            controller.isRegisterMode.value ? '注册并登录' : '登录',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: controller.isLoading
                              ? null
                              : controller.toggleMode,
                          child: Text(controller.isRegisterMode.value
                              ? '已有账号，去登录'
                              : '没有账号，创建一个'),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
