# Flutter Local Document Scanner PDF App Development Skill

## 1. Role

You are a senior Flutter mobile app engineer and computer vision engineer.

You need to help develop a fully offline Flutter document scanner app. The app should support real-time document boundary detection, camera-based document capture, perspective correction, color stamp preservation, multi-image PDF generation, local file storage, and PDF sharing.

The app must not use cloud services, OCR, large language models, account systems, or server-side APIs.

---

## 2. Project Goal

Build a Flutter app with the following core features:

1. Use the phone camera to scan paper documents.
2. Detect document boundaries in real time during camera preview.
3. Draw a quadrilateral frame over the detected document boundary.
4. Capture high-resolution photos.
5. Automatically crop and perspective-correct the document.
6. Preserve the original colors, especially red seals, blue stamps, and handwritten signatures.
7. Support adding multiple pages by taking multiple photos.
8. Support importing multiple photos from the gallery.
9. Support page management: reorder, delete, rotate, preview, and re-crop.
10. Generate a multi-page PDF locally from scanned images.
11. Save the PDF locally.
12. Share the generated PDF through the system share sheet.

---

## 3. Important Constraints

The app must be:

- Fully offline.
- Built with Flutter.
- No OCR.
- No large model.
- No cloud upload.
- No login.
- No backend.
- No third-party network API.
- Must preserve colored stamps.
- Must support multiple images/pages in one PDF.
- Must support real-time document boundary overlay while taking photos.

---

## 4. Recommended Technology Stack

Use Flutter for UI and app logic.

Recommended Flutter packages:

```yaml
dependencies:
  flutter:
    sdk: flutter

  camera: ^0.11.0
  image_picker: ^1.1.2
  permission_handler: ^11.3.1
  path_provider: ^2.1.5
  path: ^1.9.0
  pdf: ^3.11.0
  printing: ^5.13.0
  share_plus: ^10.0.0
  image: ^4.2.0
  uuid: ^4.5.0
```

For document boundary detection and perspective correction, prefer native OpenCV integration:

```text
Flutter UI
→ MethodChannel
→ Android Kotlin/Java OpenCV
→ iOS Swift/OpenCV
→ Return processed image path and corner points
```

If native OpenCV is not ready, first implement the Flutter app workflow with manual cropping and PDF generation, then add OpenCV later.

---

## 5. Suggested Project Structure

Use the following structure:

```text
lib/
├── main.dart
├── app.dart
├── routes.dart
│
├── core/
│   ├── constants/
│   ├── utils/
│   │   ├── file_utils.dart
│   │   ├── image_utils.dart
│   │   └── permission_utils.dart
│   └── services/
│       ├── document_scan_channel.dart
│       ├── pdf_service.dart
│       └── local_storage_service.dart
│
├── models/
│   ├── scan_page.dart
│   └── document_corners.dart
│
├── features/
│   ├── home/
│   │   └── home_page.dart
│   ├── scanner/
│   │   ├── scanner_page.dart
│   │   ├── camera_preview_page.dart
│   │   ├── document_border_painter.dart
│   │   └── capture_controller.dart
│   ├── crop/
│   │   ├── crop_page.dart
│   │   ├── corner_dragger.dart
│   │   └── crop_overlay_painter.dart
│   ├── pages/
│   │   ├── page_list_page.dart
│   │   └── page_thumbnail_card.dart
│   └── pdf_preview/
│       └── pdf_preview_page.dart
```

---

## 6. Main User Flow

Implement this flow:

```text
Home Page
→ New Scan
→ Camera Preview Page
→ Real-time document boundary overlay
→ Capture
→ Crop Confirmation Page
→ Perspective Correction
→ Add to Page List
→ Continue Scanning / Import From Gallery
→ Page Management
→ Generate PDF
→ PDF Preview
→ Save / Share
```

---

## 7. Camera Page Requirements

The camera page must:

1. Open the rear camera by default.
2. Request camera permission.
3. Show full-screen camera preview.
4. Display a real-time document boundary frame over the preview.
5. Provide buttons for:
   - Capture
   - Flash on/off
   - Import from gallery
   - Cancel
6. Detect document boundary every few frames instead of every frame to reduce CPU usage.
7. Use low-resolution frames for real-time detection.
8. Use high-resolution image for final cropping.

Recommended UI structure:

```dart
Stack(
  children: [
    CameraPreview(controller),
    CustomPaint(
      painter: DocumentBorderPainter(corners: detectedCorners),
      child: const SizedBox.expand(),
    ),
    Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: CaptureButton(),
    ),
  ],
)
```

---

## 8. Real-Time Boundary Detection Requirements

Real-time detection should follow this logic:

```text
Camera preview frame
→ Resize to lower resolution
→ Convert to grayscale
→ Gaussian blur
→ Canny edge detection
→ Find contours
→ Select the largest valid quadrilateral
→ Return four corner points
→ Draw overlay in Flutter
```

Requirements:

1. The detected boundary should be represented by four points:
   - topLeft
   - topRight
   - bottomRight
   - bottomLeft

2. The quadrilateral should be considered valid only if:
   - It has four corners.
   - Area is large enough.
   - It is not too narrow.
   - It is inside the camera preview.
   - It has a reasonable aspect ratio.

3. If no valid boundary is found:
   - Do not crash.
   - Hide the overlay or show a weak guide frame.
   - Allow the user to capture manually.

4. Final cropping should preferably re-detect the boundary from the captured high-resolution photo.

---

## 9. Document Border Painter Requirements

Implement a Flutter `CustomPainter` to draw the detected boundary.

Requirements:

1. Draw a quadrilateral line around the document.
2. Draw small circles on four corners.
3. Use smooth lines.
4. Support animated update if possible.
5. Do not block camera preview performance.

Example interface:

```dart
class DocumentBorderPainter extends CustomPainter {
  final List<Offset> corners;

  DocumentBorderPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(path, paint);

    final pointPaint = Paint()
      ..style = PaintingStyle.fill;

    for (final point in corners) {
      canvas.drawCircle(point, 6, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DocumentBorderPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
```

---

## 10. Crop Confirmation Page Requirements

After capture, show a crop confirmation page.

The page must:

1. Display the captured image.
2. Show four draggable corner points.
3. Allow the user to adjust document boundaries manually.
4. Prevent invalid corner crossing.
5. Provide buttons:
   - Confirm
   - Retake
   - Rotate
   - Reset auto detection
6. After confirmation, perform perspective correction.
7. Save the corrected image as a temporary local file.

This page is required because real-time boundary detection may fail in complex environments.

---

## 11. Perspective Correction Requirements

Use OpenCV perspective transform:

```text
Input image + four corner points
→ Sort points
→ Calculate target rectangle width and height
→ getPerspectiveTransform
→ warpPerspective
→ Output corrected document image
```

Point order must be:

```text
topLeft
topRight
bottomRight
bottomLeft
```

The corrected output should preserve RGB color.

Do not convert the final document to black and white by default.

---

## 12. Color Stamp Preservation Requirements

The app must preserve red seals, blue stamps, and colored signatures.

Do not use full-page binarization as default.

Default mode should be:

```text
Color Enhanced Mode
```

Recommended scan modes:

```text
1. Original Color
2. Color Enhanced
3. Black and White
```

Default:

```text
Color Enhanced
```

Color Enhanced Mode requirements:

1. Keep RGB color.
2. Improve brightness and contrast gently.
3. Reduce shadow slightly.
4. Sharpen text slightly.
5. Do not destroy red or blue areas.
6. Do not convert the entire image to grayscale.
7. Do not apply global thresholding to the whole page.

Optional advanced stamp preservation:

```text
Convert image to HSV
Detect red mask:
  H around 0-10 and 160-180
  S high
  V medium/high

Detect blue mask:
  H around 90-130
  S high
  V medium/high

Enhance non-stamp regions
Keep stamp regions from original image
Blend final image
```

---

## 13. Multi-Page PDF Requirements

The app must support multiple pages.

Each scanned page should be represented by:

```dart
class ScanPage {
  final String id;
  final String originalImagePath;
  final String processedImagePath;
  final DateTime createdAt;
  final int rotation;
}
```

Page list features:

1. Add page from camera.
2. Add page from gallery.
3. Delete page.
4. Reorder pages.
5. Rotate page.
6. Preview page.
7. Re-crop page.
8. Generate PDF.

---

## 14. PDF Generation Requirements

Use the Flutter `pdf` package.

Requirements:

1. Each scanned image becomes one PDF page.
2. PDF page size should default to A4.
3. Preserve image aspect ratio.
4. Use `BoxFit.contain` or equivalent.
5. Allow basic compression.
6. Generate PDF locally.
7. Save PDF to app document directory.
8. Support sharing with `share_plus`.

Example logic:

```dart
final pdf = pw.Document();

for (final page in pages) {
  final imageBytes = await File(page.processedImagePath).readAsBytes();
  final image = pw.MemoryImage(imageBytes);

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Center(
          child: pw.Image(
            image,
            fit: pw.BoxFit.contain,
          ),
        );
      },
    ),
  );
}

final outputDir = await getApplicationDocumentsDirectory();
final file = File('${outputDir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.pdf');
await file.writeAsBytes(await pdf.save());
```

---

## 15. Performance Requirements

The app must be optimized for mobile devices.

Rules:

1. Do not process full-resolution images for real-time preview.
2. Process preview frames at low resolution.
3. Detect boundaries every 3 to 5 frames, not every frame.
4. Use native OpenCV for heavy image processing.
5. Use isolates or native threads for time-consuming processing.
6. Avoid loading all full-resolution images into memory at once.
7. Save processed pages as temporary JPEG files.
8. Generate PDF page by page.
9. Release camera and image resources correctly.
10. Avoid UI freezing.

---

## 16. Android Requirements

Android implementation should:

1. Use camera permission.
2. Handle storage permissions based on Android version.
3. Use app-specific storage where possible.
4. Handle EXIF rotation correctly.
5. Normalize image orientation before detection and cropping.
6. Integrate OpenCV if real-time detection is implemented natively.

Important Android issues to handle:

```text
Preview size != screen size
Captured image size != preview size
EXIF orientation may rotate image
Coordinate mapping may be incorrect
Different devices have different camera behavior
```

If coordinate mapping becomes unstable, use real-time detection only as visual guidance and re-detect the document boundary from the captured high-resolution image.

---

## 17. iOS Requirements

iOS implementation should:

1. Request camera and photo library permissions.
2. Support local file storage.
3. Handle image orientation correctly.
4. Support native OpenCV or equivalent image processing if needed.
5. Support PDF sharing through the iOS share sheet.

---

## 18. Error Handling

Handle these cases:

1. Camera permission denied.
2. No camera available.
3. Boundary not detected.
4. User captures without boundary.
5. Image processing failed.
6. PDF generation failed.
7. No pages selected.
8. File save failed.
9. Share failed.
10. Low memory while processing large images.

Do not crash. Show clear user-friendly messages.

---

## 19. Development Order

Implement the project in this order:

### Phase 1: Basic Workflow

1. Create Flutter project.
2. Add camera permission.
3. Open camera preview.
4. Capture photo.
5. Save photo locally.
6. Show captured photo.

### Phase 2: Multi-Page Management

1. Add captured image to page list.
2. Support multiple captures.
3. Support gallery import.
4. Support delete and reorder pages.

### Phase 3: PDF Generation

1. Generate PDF from selected images.
2. Save PDF locally.
3. Preview PDF.
4. Share PDF.

### Phase 4: Manual Crop

1. Add crop confirmation page.
2. Add draggable four corners.
3. Add perspective correction.
4. Save corrected image.

### Phase 5: Auto Detection

1. Add OpenCV-based document boundary detection after capture.
2. Auto-fill crop corners.
3. Allow manual correction.

### Phase 6: Real-Time Boundary Overlay

1. Analyze preview frames.
2. Detect document boundary in real time.
3. Draw quadrilateral overlay.
4. Optimize performance.

### Phase 7: Color Enhancement and Stamp Preservation

1. Add original color mode.
2. Add color enhanced mode.
3. Avoid full-page black-white conversion.
4. Add optional red/blue stamp protection.

---

## 20. Coding Rules

When writing code:

1. Use clean and modular Flutter architecture.
2. Keep UI code and business logic separated.
3. Use descriptive class and method names.
4. Add comments for complex image-processing logic.
5. Avoid hard-coded paths.
6. Use app document/cache directories.
7. Keep all processing local.
8. Do not add network dependencies.
9. Do not add OCR dependencies.
10. Do not add AI model dependencies.
11. Do not implement login or backend.
12. Make the code easy to run on Android first.
13. Keep iOS compatibility in mind.

---

## 21. Expected Deliverables

Generate code for:

1. Flutter project structure.
2. Camera preview page.
3. Real-time boundary overlay painter.
4. Capture image flow.
5. Page list management.
6. Gallery import.
7. PDF generation service.
8. PDF preview/share page.
9. Manual crop UI.
10. Native OpenCV MethodChannel design.
11. Android OpenCV document detection implementation.
12. Perspective correction implementation.
13. Color enhancement mode that preserves colored seals.

---

## 22. Do Not Implement

Do not implement:

1. OCR.
2. Text recognition.
3. Large language model.
4. Cloud upload.
5. Server API.
6. User login.
7. Database server.
8. Online sync.
9. Subscription/payment.
10. Advertisement system.

---

## 23. Acceptance Criteria

The app is considered acceptable when:

1. It can open the phone camera.
2. It can show a live camera preview.
3. It can display a real-time document boundary frame.
4. It can capture a photo.
5. It can crop and perspective-correct the document.
6. It can preserve colored stamps.
7. It can scan multiple pages.
8. It can import multiple photos from the gallery.
9. It can reorder and delete pages.
10. It can generate a multi-page PDF locally.
11. It can save and share the PDF.
12. It works without internet connection.
13. It does not use OCR or AI models.

---

# Short Prompt Version

请基于 Flutter 开发一个纯本地文件扫描 PDF App。

要求：

1. 不需要 OCR。
2. 不需要大模型。
3. 不需要服务器。
4. 不上传任何文件。
5. 支持手机拍照扫描文件。
6. 拍照时要实时检测文件边界，并在相机预览界面绘制四边形边框。
7. 支持拍照后手动调整四个角点。
8. 支持自动裁剪和透视矫正。
9. 默认保留彩色图像，尤其要保留红色印章、蓝色印章和手写签名。
10. 支持多张照片作为多页文档。
11. 支持从相册导入多张图片。
12. 支持页面排序、删除、旋转、重新裁剪。
13. 支持把多张图片合成为一个 PDF。
14. PDF 在本地生成、保存和分享。
15. 优先实现 Android，兼顾 iOS。

技术路线：

Flutter + camera + CustomPainter + pdf + share_plus + path_provider。

图像处理部分优先通过 Flutter MethodChannel 调用 Android/iOS 原生 OpenCV。

实时边界检测使用低分辨率预览帧，最终裁剪使用高清拍照图片。

不要默认黑白二值化，默认使用彩色增强模式，避免破坏彩色印章。

请按照以下阶段开发：

第一阶段：相机拍照和本地保存。  
第二阶段：多页图片列表管理。  
第三阶段：多图合成 PDF。  
第四阶段：手动四角裁剪。  
第五阶段：OpenCV 自动边界检测和透视矫正。  
第六阶段：相机预览实时边界框绘制。  
第七阶段：彩色增强和印章保留优化。

请生成完整、可运行、模块化的代码，并说明每个文件的作用。
