import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  const PermissionUtils._();

  static Future<bool> ensureCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }
}
