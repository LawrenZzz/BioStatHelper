import 'package:get/get.dart';
import '../controllers/concepts_controller.dart';

class ConceptsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ConceptsController>(
      () => ConceptsController(),
    );
  }
}
