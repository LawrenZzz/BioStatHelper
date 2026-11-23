import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/services/auth_service.dart';
import '../../../routes/app_routes.dart';

class AuthController extends GetxController {
  final AuthService _authService = Get.find<AuthService>();

  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final isRegisterMode = false.obs;

  bool get isLoading => _authService.isLoading.value;

  @override
  void onClose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  void toggleMode() {
    isRegisterMode.value = !isRegisterMode.value;
  }

  Future<void> submit() async {
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      Get.snackbar('提示', '请输入用户名和密码');
      return;
    }

    if (isRegisterMode.value && email.isEmpty) {
      Get.snackbar('提示', '请输入邮箱');
      return;
    }

    final success = isRegisterMode.value
        ? await _authService.register(username, email, password)
        : await _authService.login(username, password);

    if (success) {
      Get.offAllNamed(AppRoutes.shell);
    }
  }
}
