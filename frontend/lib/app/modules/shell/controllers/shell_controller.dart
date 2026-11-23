import 'package:get/get.dart';

class ShellController extends GetxController {
  final currentIndex = 1.obs;
  final RxBool sidebarCollapsed = false.obs;

  void switchTab(int index) {
    if (index == currentIndex.value) return;
    currentIndex.value = index;
  }

  void toggleSidebar() => sidebarCollapsed.value = !sidebarCollapsed.value;
}
