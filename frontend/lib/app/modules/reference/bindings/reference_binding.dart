import 'package:get/get.dart';
import '../controllers/reference_controller.dart';

class ReferenceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ReferenceController>(
      () => ReferenceController(),
    );
  }
}
