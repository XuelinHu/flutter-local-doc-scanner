import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = const [];
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = const [];
  }

  runApp(DocumentScannerApp(cameras: cameras));
}
