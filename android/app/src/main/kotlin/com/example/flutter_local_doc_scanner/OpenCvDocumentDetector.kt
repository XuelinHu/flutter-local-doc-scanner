package com.example.flutter_local_doc_scanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

object OpenCvDocumentDetector {
    private const val MAX_DETECT_SIDE = 1600.0
    private const val MAX_DECODE_SIDE_FOR_OUTPUT = 4200
    private const val MIN_AREA_RATIO = 0.12

    fun getImageInfo(imagePath: String): Map<String, Double>? {
        val bounds = readBounds(imagePath) ?: return null
        return mapOf(
            "width" to bounds.first.toDouble(),
            "height" to bounds.second.toDouble(),
        )
    }

    fun createPreviewImage(
        imagePath: String,
        outputDir: String,
        maxSide: Int = 1600,
    ): String? {
        val bitmap = decodeAndNormalizeBitmap(imagePath, maxSide) ?: return null
        return saveBitmap(bitmap, outputDir, "preview", 88)
    }

    fun rotateImage(imagePath: String, outputDir: String): String? {
        val bitmap = decodeAndNormalizeBitmap(imagePath, MAX_DECODE_SIDE_FOR_OUTPUT) ?: return null
        val matrix = Matrix().apply { postRotate(90f) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated != bitmap) {
            bitmap.recycle()
        }
        return saveBitmap(rotated, outputDir, "rotated", 94)
    }

    fun detectDocument(imagePath: String): Map<String, Map<String, Double>>? {
        val info = readBounds(imagePath) ?: return null
        val bitmap = decodeAndNormalizeBitmap(imagePath, MAX_DETECT_SIDE.toInt()) ?: return null
        val normalizedWidth = info.first.toDouble()
        val normalizedHeight = info.second.toDouble()
        val scaleX = bitmap.width.toDouble() / normalizedWidth
        val scaleY = bitmap.height.toDouble() / normalizedHeight

        val rgba = Mat()
        Utils.bitmapToMat(bitmap, rgba)
        bitmap.recycle()

        val gray = Mat()
        val blurred = Mat()
        val edges = Mat()
        val adaptiveEdges = Mat()

        try {
            Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)
            Imgproc.Canny(blurred, edges, 60.0, 180.0)
            Imgproc.adaptiveThreshold(
                blurred,
                adaptiveEdges,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY,
                31,
                8.0,
            )

            val kernel = Imgproc.getStructuringElement(
                Imgproc.MORPH_RECT,
                Size(5.0, 5.0),
            )
            Imgproc.morphologyEx(edges, edges, Imgproc.MORPH_CLOSE, kernel)
            Imgproc.morphologyEx(adaptiveEdges, adaptiveEdges, Imgproc.MORPH_CLOSE, kernel)
            kernel.release()

            val contours = mutableListOf<MatOfPoint>()
            findContours(edges, contours)
            findContours(adaptiveEdges, contours)

            val imageArea = rgba.width().toDouble() * rgba.height().toDouble()
            var bestCandidate: DocumentCandidate? = null

            for (contour in contours) {
                val contourArea = Imgproc.contourArea(contour)
                if (contourArea < imageArea * MIN_AREA_RATIO) {
                    continue
                }

                val contour2f = MatOfPoint2f(*contour.toArray())
                val perimeter = Imgproc.arcLength(contour2f, true)
                for (epsilonRatio in listOf(0.012, 0.018, 0.025, 0.035)) {
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(contour2f, approx, perimeter * epsilonRatio, true)
                    val approxPoints = approx.toArray()
                    approx.release()
                    if (approxPoints.size != 4) {
                        continue
                    }

                    val approxMat = MatOfPoint(*approxPoints)
                    val isConvex = Imgproc.isContourConvex(approxMat)
                    approxMat.release()
                    if (!isConvex) {
                        continue
                    }

                    val ordered = orderCorners(approxPoints.toList())
                    if (!isValidQuadrilateral(ordered, rgba.width().toDouble(), rgba.height().toDouble())) {
                        continue
                    }

                    val candidate = DocumentCandidate(
                        points = ordered,
                        score = quadrilateralScore(
                            ordered,
                            rgba.width().toDouble(),
                            rgba.height().toDouble(),
                        ),
                    )
                    if (bestCandidate == null || candidate.score > bestCandidate.score) {
                        bestCandidate = candidate
                    }
                }
                contour2f.release()
            }

            contours.forEach { it.release() }

            val mapped = bestCandidate?.points?.map { point ->
                Point(point.x / scaleX, point.y / scaleY)
            } ?: return null

            return mapOf(
                "topLeft" to pointMap(mapped[0]),
                "topRight" to pointMap(mapped[1]),
                "bottomRight" to pointMap(mapped[2]),
                "bottomLeft" to pointMap(mapped[3]),
            )
        } finally {
            rgba.release()
            gray.release()
            blurred.release()
            edges.release()
            adaptiveEdges.release()
        }

        return null
    }

    fun detectPreviewFrame(
        bytes: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        rotationDegrees: Int,
    ): Map<String, Any>? {
        if (width <= 0 || height <= 0 || rowStride < width) {
            return null
        }

        val source = Mat(height, rowStride, CvType.CV_8UC1)
        val gray = Mat()
        val upright = Mat()
        val resized = Mat()
        try {
            source.put(0, 0, bytes)
            source.submat(0, height, 0, width).copyTo(gray)
            when ((rotationDegrees % 360 + 360) % 360) {
                90 -> Core.rotate(gray, upright, Core.ROTATE_90_CLOCKWISE)
                180 -> Core.rotate(gray, upright, Core.ROTATE_180)
                270 -> Core.rotate(gray, upright, Core.ROTATE_90_COUNTERCLOCKWISE)
                else -> gray.copyTo(upright)
            }

            val longestSide = max(upright.width(), upright.height()).toDouble()
            val scale = min(1.0, 720.0 / longestSide)
            if (scale < 1.0) {
                Imgproc.resize(
                    upright,
                    resized,
                    Size(upright.width() * scale, upright.height() * scale),
                    0.0,
                    0.0,
                    Imgproc.INTER_AREA,
                )
            } else {
                upright.copyTo(resized)
            }

            val detected = findDocumentCorners(resized) ?: return null
            val mapped = detected.map { point ->
                Point(point.x / scale, point.y / scale)
            }
            return mapOf(
                "imageWidth" to upright.width().toDouble(),
                "imageHeight" to upright.height().toDouble(),
                "topLeft" to pointMap(mapped[0]),
                "topRight" to pointMap(mapped[1]),
                "bottomRight" to pointMap(mapped[2]),
                "bottomLeft" to pointMap(mapped[3]),
            )
        } finally {
            source.release()
            gray.release()
            upright.release()
            resized.release()
        }
    }

    fun processDocument(
        imagePath: String,
        outputDir: String,
        corners: List<Point>,
        mode: String,
        maxSide: Int = 3508,
    ): String? {
        if (corners.size != 4) {
            return null
        }

        val info = readBounds(imagePath) ?: return null
        val bitmap = decodeAndNormalizeBitmap(imagePath, MAX_DECODE_SIDE_FOR_OUTPUT) ?: return null
        val scaleX = bitmap.width.toDouble() / info.first.toDouble()
        val scaleY = bitmap.height.toDouble() / info.second.toDouble()
        val scaledCorners = corners.map { Point(it.x * scaleX, it.y * scaleY) }

        val targetSize = targetSizeFor(scaledCorners, maxSide)
        val srcPoints = MatOfPoint2f(*scaledCorners.toTypedArray())
        val dstPoints = MatOfPoint2f(
            Point(0.0, 0.0),
            Point(targetSize.width - 1.0, 0.0),
            Point(targetSize.width - 1.0, targetSize.height - 1.0),
            Point(0.0, targetSize.height - 1.0),
        )

        val rgba = Mat()
        val warpedRgba = Mat()
        val bgr = Mat()
        val output = Mat()
        Utils.bitmapToMat(bitmap, rgba)
        bitmap.recycle()

        try {
            val transform = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
            Imgproc.warpPerspective(
                rgba,
                warpedRgba,
                transform,
                Size(targetSize.width, targetSize.height),
                Imgproc.INTER_LINEAR,
                Core.BORDER_CONSTANT,
                Scalar(255.0, 255.0, 255.0, 255.0),
            )
            transform.release()

            Imgproc.cvtColor(warpedRgba, bgr, Imgproc.COLOR_RGBA2BGR)
            val processed = when (mode) {
                "blackWhite" -> applyBlackWhite(bgr)
                "originalColor" -> bgr.clone()
                else -> applyColorEnhanced(bgr)
            }
            processed.copyTo(output)
            processed.release()

            val file = File(outputDir, "scan_page_${UUID.randomUUID()}.jpg")
            return if (Imgcodecs.imwrite(file.absolutePath, output)) {
                file.absolutePath
            } else {
                null
            }
        } finally {
            rgba.release()
            warpedRgba.release()
            bgr.release()
            output.release()
            srcPoints.release()
            dstPoints.release()
        }
    }

    private fun applyColorEnhanced(src: Mat): Mat {
        val lab = Mat()
        val enhancedLab = Mat()
        val result = Mat()
        Imgproc.cvtColor(src, lab, Imgproc.COLOR_BGR2Lab)
        val channels = mutableListOf<Mat>()
        Core.split(lab, channels)

        val clahe = Imgproc.createCLAHE(1.6, Size(8.0, 8.0))
        clahe.apply(channels[0], channels[0])
        Core.merge(channels, enhancedLab)
        Imgproc.cvtColor(enhancedLab, result, Imgproc.COLOR_Lab2BGR)
        result.convertTo(result, -1, 1.05, 4.0)

        val blurred = Mat()
        Imgproc.GaussianBlur(result, blurred, Size(0.0, 0.0), 1.0)
        Core.addWeighted(result, 1.25, blurred, -0.25, 0.0, result)

        channels.forEach { it.release() }
        blurred.release()
        lab.release()
        enhancedLab.release()
        return result
    }

    private fun findDocumentCorners(gray: Mat): List<Point>? {
        val blurred = Mat()
        val edges = Mat()
        val adaptiveEdges = Mat()
        try {
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)
            Imgproc.Canny(blurred, edges, 60.0, 180.0)
            Imgproc.adaptiveThreshold(
                blurred,
                adaptiveEdges,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY,
                31,
                8.0,
            )

            val kernel = Imgproc.getStructuringElement(
                Imgproc.MORPH_RECT,
                Size(5.0, 5.0),
            )
            Imgproc.morphologyEx(edges, edges, Imgproc.MORPH_CLOSE, kernel)
            Imgproc.morphologyEx(adaptiveEdges, adaptiveEdges, Imgproc.MORPH_CLOSE, kernel)
            kernel.release()

            val contours = mutableListOf<MatOfPoint>()
            findContours(edges, contours)
            findContours(adaptiveEdges, contours)
            val imageArea = gray.width().toDouble() * gray.height().toDouble()
            var bestCandidate: DocumentCandidate? = null

            for (contour in contours) {
                if (Imgproc.contourArea(contour) < imageArea * MIN_AREA_RATIO) {
                    continue
                }

                val contour2f = MatOfPoint2f(*contour.toArray())
                val perimeter = Imgproc.arcLength(contour2f, true)
                for (epsilonRatio in listOf(0.012, 0.018, 0.025, 0.035)) {
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(contour2f, approx, perimeter * epsilonRatio, true)
                    val approxPoints = approx.toArray()
                    approx.release()
                    if (approxPoints.size != 4) {
                        continue
                    }

                    val approxMat = MatOfPoint(*approxPoints)
                    val isConvex = Imgproc.isContourConvex(approxMat)
                    approxMat.release()
                    if (!isConvex) {
                        continue
                    }

                    val ordered = orderCorners(approxPoints.toList())
                    if (!isValidQuadrilateral(
                            ordered,
                            gray.width().toDouble(),
                            gray.height().toDouble(),
                        )
                    ) {
                        continue
                    }

                    val candidate = DocumentCandidate(
                        points = ordered,
                        score = quadrilateralScore(
                            ordered,
                            gray.width().toDouble(),
                            gray.height().toDouble(),
                        ),
                    )
                    if (bestCandidate == null || candidate.score > bestCandidate.score) {
                        bestCandidate = candidate
                    }
                }
                contour2f.release()
            }

            contours.forEach { it.release() }
            return bestCandidate?.points
        } finally {
            blurred.release()
            edges.release()
            adaptiveEdges.release()
        }
    }

    private fun applyBlackWhite(src: Mat): Mat {
        val gray = Mat()
        val enhanced = Mat()
        val result = Mat()
        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)
        val clahe = Imgproc.createCLAHE(2.0, Size(8.0, 8.0))
        clahe.apply(gray, enhanced)
        Imgproc.adaptiveThreshold(
            enhanced,
            enhanced,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY,
            31,
            8.0,
        )
        Imgproc.cvtColor(enhanced, result, Imgproc.COLOR_GRAY2BGR)
        gray.release()
        enhanced.release()
        return result
    }

    private fun saveBitmap(bitmap: Bitmap, outputDir: String, prefix: String, quality: Int): String? {
        val file = File(outputDir, "${prefix}_${UUID.randomUUID()}.jpg")
        return try {
            file.outputStream().use { stream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
            }
            file.absolutePath
        } finally {
            bitmap.recycle()
        }
    }

    private fun readBounds(imagePath: String): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(imagePath, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) {
            return null
        }

        return if (isRotated(imagePath)) {
            options.outHeight to options.outWidth
        } else {
            options.outWidth to options.outHeight
        }
    }

    private fun decodeAndNormalizeBitmap(imagePath: String, maxSide: Int): Bitmap? {
        val rawBounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(imagePath, rawBounds)
        if (rawBounds.outWidth <= 0 || rawBounds.outHeight <= 0) {
            return null
        }

        val sampleSize = calculateSampleSize(rawBounds.outWidth, rawBounds.outHeight, maxSide)
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sampleSize
        }
        val source = BitmapFactory.decodeFile(imagePath, options) ?: return null
        val orientation = readOrientation(imagePath)

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
        }

        return if (matrix.isIdentity) {
            source
        } else {
            Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true).also {
                if (it != source) {
                    source.recycle()
                }
            }
        }
    }

    private fun calculateSampleSize(width: Int, height: Int, maxSide: Int): Int {
        var sampleSize = 1
        var longest = max(width, height)
        while (longest / 2 >= maxSide) {
            sampleSize *= 2
            longest /= 2
        }
        return sampleSize
    }

    private fun targetSizeFor(points: List<Point>, maxSide: Int): TargetSize {
        val topWidth = distance(points[0], points[1])
        val bottomWidth = distance(points[3], points[2])
        val leftHeight = distance(points[0], points[3])
        val rightHeight = distance(points[1], points[2])

        var width = max(topWidth, bottomWidth)
        var height = max(leftHeight, rightHeight)
        val longest = max(width, height)
        if (longest > maxSide) {
            val scale = maxSide / longest
            width *= scale
            height *= scale
        }

        return TargetSize(
            width = width.coerceAtLeast(300.0),
            height = height.coerceAtLeast(300.0),
        )
    }

    private fun readOrientation(imagePath: String): Int {
        return try {
            ExifInterface(imagePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: IOException) {
            ExifInterface.ORIENTATION_NORMAL
        }
    }

    private fun isRotated(imagePath: String): Boolean {
        return when (readOrientation(imagePath)) {
            ExifInterface.ORIENTATION_ROTATE_90,
            ExifInterface.ORIENTATION_ROTATE_270 -> true
            else -> false
        }
    }

    private fun orderCorners(points: List<Point>): List<Point> {
        val sortedByY = points.sortedWith(compareBy<Point> { it.y }.thenBy { it.x })
        val top = sortedByY.take(2).sortedBy { it.x }
        val bottom = sortedByY.takeLast(2).sortedBy { it.x }
        return listOf(top[0], top[1], bottom[1], bottom[0])
    }

    private fun isValidQuadrilateral(
        points: List<Point>,
        width: Double,
        height: Double,
    ): Boolean {
        if (points.size != 4) {
            return false
        }

        val areaMat = MatOfPoint(*points.toTypedArray())
        val area = abs(Imgproc.contourArea(areaMat))
        areaMat.release()
        if (area < width * height * MIN_AREA_RATIO) {
            return false
        }

        val topWidth = distance(points[0], points[1])
        val bottomWidth = distance(points[3], points[2])
        val leftHeight = distance(points[0], points[3])
        val rightHeight = distance(points[1], points[2])

        if (topWidth < width * 0.2 || bottomWidth < width * 0.2) {
            return false
        }
        if (leftHeight < height * 0.2 || rightHeight < height * 0.2) {
            return false
        }

        val avgWidth = (topWidth + bottomWidth) / 2.0
        val avgHeight = (leftHeight + rightHeight) / 2.0
        val aspectRatio = avgWidth / avgHeight
        if (aspectRatio < 0.5 || aspectRatio > 2.2) {
            return false
        }

        return points.all { point ->
            point.x in 0.0..width && point.y in 0.0..height
        }
    }

    private fun quadrilateralScore(points: List<Point>, width: Double, height: Double): Double {
        val polygon = MatOfPoint(*points.toTypedArray())
        val areaRatio = abs(Imgproc.contourArea(polygon)) / (width * height)
        polygon.release()

        val top = distance(points[0], points[1])
        val right = distance(points[1], points[2])
        val bottom = distance(points[2], points[3])
        val left = distance(points[3], points[0])
        val oppositeSideQuality =
            min(top, bottom) / max(top, bottom) + min(left, right) / max(left, right)

        val rightAngleQuality = points.indices.sumOf { index ->
            cornerRightAngleQuality(
                points[(index + 3) % 4],
                points[index],
                points[(index + 1) % 4],
            )
        } / 4.0

        val borderMargin = minOf(
            points.minOf { it.x },
            points.minOf { it.y },
            width - points.maxOf { it.x },
            height - points.maxOf { it.y },
        )
        val hugsImageBorder = areaRatio > 0.93 && borderMargin < min(width, height) * 0.012
        val borderPenalty = if (hugsImageBorder) 1.5 else 0.0

        return areaRatio * 5.0 + oppositeSideQuality + rightAngleQuality - borderPenalty
    }

    private fun findContours(source: Mat, destination: MutableList<MatOfPoint>) {
        val hierarchy = Mat()
        val contours = mutableListOf<MatOfPoint>()
        Imgproc.findContours(
            source,
            contours,
            hierarchy,
            Imgproc.RETR_LIST,
            Imgproc.CHAIN_APPROX_SIMPLE,
        )
        hierarchy.release()
        destination.addAll(contours)
    }

    private fun cornerRightAngleQuality(previous: Point, corner: Point, next: Point): Double {
        val ax = previous.x - corner.x
        val ay = previous.y - corner.y
        val bx = next.x - corner.x
        val by = next.y - corner.y
        val denominator = sqrt((ax * ax + ay * ay) * (bx * bx + by * by))
        if (denominator == 0.0) {
            return 0.0
        }
        return 1.0 - abs((ax * bx + ay * by) / denominator)
    }

    private fun distance(a: Point, b: Point): Double {
        val dx = a.x - b.x
        val dy = a.y - b.y
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    private fun pointMap(point: Point): Map<String, Double> {
        return mapOf(
            "x" to point.x,
            "y" to point.y,
        )
    }
}

private data class TargetSize(
    val width: Double,
    val height: Double,
)

private data class DocumentCandidate(
    val points: List<Point>,
    val score: Double,
)
