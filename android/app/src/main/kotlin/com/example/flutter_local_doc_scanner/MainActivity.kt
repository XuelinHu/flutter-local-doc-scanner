package com.example.flutter_local_doc_scanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.core.Point
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val openCvReady = OpenCVLoader.initLocal()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "local_doc_scanner/document_scan",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getImageInfo" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    result.success(OpenCvDocumentDetector.getImageInfo(imagePath))
                }

                "detectDocument" -> {
                    if (!openCvReady) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    worker.execute {
                        val corners = OpenCvDocumentDetector.detectDocument(imagePath)
                        runOnUiThread { result.success(corners) }
                    }
                }

                "detectPreviewFrame" -> {
                    if (!openCvReady) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val bytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    val rowStride = call.argument<Int>("rowStride")
                    val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                    if (bytes == null || width == null || height == null || rowStride == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    worker.execute {
                        val corners = OpenCvDocumentDetector.detectPreviewFrame(
                            bytes = bytes,
                            width = width,
                            height = height,
                            rowStride = rowStride,
                            rotationDegrees = rotationDegrees,
                        )
                        runOnUiThread { result.success(corners) }
                    }
                }

                "createPreviewImage" -> {
                    if (!openCvReady) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val imagePath = call.argument<String>("imagePath")
                    val outputDir = call.argument<String>("outputDir")
                    val maxSide = call.argument<Int>("maxSide") ?: 1600
                    if (imagePath.isNullOrBlank() || outputDir.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val path = OpenCvDocumentDetector.createPreviewImage(
                            imagePath = imagePath,
                            outputDir = outputDir,
                            maxSide = maxSide,
                        )
                        runOnUiThread { result.success(path) }
                    }
                }

                "processDocument" -> {
                    if (!openCvReady) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val imagePath = call.argument<String>("imagePath")
                    val outputDir = call.argument<String>("outputDir")
                    val maxSide = call.argument<Int>("maxSide") ?: 3508
                    val mode = call.argument<String>("mode") ?: "colorEnhanced"
                    if (imagePath.isNullOrBlank() || outputDir.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val corners = listOf(
                        Point(call.argument<Double>("topLeftX") ?: 0.0, call.argument<Double>("topLeftY") ?: 0.0),
                        Point(call.argument<Double>("topRightX") ?: 0.0, call.argument<Double>("topRightY") ?: 0.0),
                        Point(call.argument<Double>("bottomRightX") ?: 0.0, call.argument<Double>("bottomRightY") ?: 0.0),
                        Point(call.argument<Double>("bottomLeftX") ?: 0.0, call.argument<Double>("bottomLeftY") ?: 0.0),
                    )
                    worker.execute {
                        val path = OpenCvDocumentDetector.processDocument(
                            imagePath = imagePath,
                            outputDir = outputDir,
                            corners = corners,
                            mode = mode,
                            maxSide = maxSide,
                        )
                        runOnUiThread { result.success(path) }
                    }
                }

                "rotateImage" -> {
                    if (!openCvReady) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val imagePath = call.argument<String>("imagePath")
                    val outputDir = call.argument<String>("outputDir")
                    if (imagePath.isNullOrBlank() || outputDir.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val path = OpenCvDocumentDetector.rotateImage(
                            imagePath = imagePath,
                            outputDir = outputDir,
                        )
                        runOnUiThread { result.success(path) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
