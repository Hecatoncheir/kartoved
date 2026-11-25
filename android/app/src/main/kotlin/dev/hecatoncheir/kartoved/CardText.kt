package dev.hecatoncheir.kartoved

import android.content.Context
import android.graphics.*
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.languageid.LanguageIdentificationOptions
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class CardText(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val identifier = LanguageIdentification.getClient(
        LanguageIdentificationOptions.Builder().setConfidenceThreshold(0.75f).build()
    )
    private var engine: TessBaseAPI? = null

    fun read(call: MethodCall, reply: MethodChannel.Result) {
        process(reply) {
            recognize(textRegions(bitmap(call), call.argument<List<Double>>("corners")))
        }
    }

    fun photo(call: MethodCall, reply: MethodChannel.Result) {
        process(reply) {
            val source = bitmap(call)
            try {
                val points = call.argument<List<Double>>("corners")
                val card = straighten(source, points) ?: thumbnail(source)
                try {
                    ByteArrayOutputStream().use { out ->
                        if (card.compress(Bitmap.CompressFormat.JPEG, 88, out)) out.toByteArray() else null
                    }
                } finally {
                    if (card !== source) card.recycle()
                }
            } finally {
                source.recycle()
            }
        }
    }

    private fun thumbnail(source: Bitmap): Bitmap {
        val largerSide = maxOf(source.width, source.height)
        if (largerSide <= 840) return source
        return Bitmap.createScaledBitmap(
            source,
            (source.width * 840 / largerSide).coerceAtLeast(1),
            (source.height * 840 / largerSide).coerceAtLeast(1),
            true,
        )
    }

    private fun process(reply: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            val result = runCatching(work).getOrNull()
            android.os.Handler(context.mainLooper).post { reply.success(result) }
        }
    }

    fun warmTray(reply: MethodChannel.Result) = process(reply) {
        if (engine == null) engine = open()
        null
    }

    fun trayPhoto(call: MethodCall, reply: MethodChannel.Result) = process(reply) {
        val bounds = requireNotNull(call.argument<List<Double>>("tray"))
        val source = bitmap(call)
        val card = try {
            val rect = Rect(
                (bounds[0] * source.width).toInt(), (bounds[1] * source.height).toInt(),
                (bounds[2] * source.width).toInt(), (bounds[3] * source.height).toInt(),
            )
            Bitmap.createBitmap(600, 840, Bitmap.Config.ARGB_8888).also {
                Canvas(it).drawBitmap(source, rect, Rect(0, 0, 600, 840), Paint(Paint.FILTER_BITMAP_FLAG))
            }
        } finally {
            source.recycle()
        }
        try {
            val footer = if (call.argument<Boolean>("readFooter") == true) {
                runCatching { trayFooter(card) }.getOrDefault("")
            } else ""
            ByteArrayOutputStream().use { out ->
                if (card.compress(Bitmap.CompressFormat.JPEG, 88, out)) {
                    mapOf("bytes" to out.toByteArray(), "footer" to footer)
                } else null
            }
        } finally {
            card.recycle()
        }
    }

    private fun trayFooter(card: Bitmap): String {
        val api = engine ?: open().also { engine = it }
        val original = api.pageSegMode
        val footer = Bitmap.createBitmap(card, 0, 730, 440, 110)
        try {
            api.pageSegMode = TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK
            api.setImage(footer)
            return api.getUTF8Text().orEmpty()
        } finally {
            api.clear()
            api.pageSegMode = original
            footer.recycle()
        }
    }

    fun readTrayText(call: MethodCall, reply: MethodChannel.Result) = process(reply) {
        val bytes = requireNotNull(call.arguments as? ByteArray)
        val card = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        maskArtwork(card)
        recognize(card)
    }

    private fun recognize(bitmap: Bitmap): Map<String, String> {
        val api = engine ?: open().also { engine = it }
        try {
            api.setImage(bitmap)
            val text = api.getUTF8Text().orEmpty()
            val language = runCatching { Tasks.await(identifier.identifyLanguage(text)) }.getOrDefault("und")
            return mapOf("text" to text, "language" to language)
        } finally {
            api.clear()
            bitmap.recycle()
        }
    }

    private fun textRegions(source: Bitmap, points: List<Double>?): Bitmap {
        val page = straighten(source, points) ?: return source
        source.recycle()
        maskArtwork(page)
        return page
    }

    private fun maskArtwork(page: Bitmap) {
        val width = page.width.toFloat()
        val height = page.height.toFloat()
        // Иллюстрация между названием и текстом правил даёт ложные буквы.
        Canvas(page).drawRect(0f, height * .15f, width, height * .53f, Paint().apply { color = Color.WHITE })
    }

    private fun straighten(source: Bitmap, points: List<Double>?): Bitmap? {
        if (points?.size != 8 || points.any { !it.isFinite() }) return null
        val width = 600
        val height = 840
        val from = FloatArray(8) { i ->
            (points[i] * if (i % 2 == 0) source.width else source.height).toFloat()
        }
        val target = floatArrayOf(0f, 0f, width.toFloat(), 0f, width.toFloat(), height.toFloat(), 0f, height.toFloat())
        val transform = Matrix()
        if (!transform.setPolyToPoly(from, 0, target, 0, 4)) return null
        val page = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(page)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(source, transform, Paint(Paint.FILTER_BITMAP_FLAG))
        return page
    }

    private fun open(): TessBaseAPI {
        val root = File(context.filesDir, "ocr-1")
        val data = File(root, "tessdata")
        data.mkdirs()
        for (lang in listOf("eng", "rus")) {
            val file = File(data, "$lang.traineddata")
            if (file.exists()) continue
            val temp = File(data, "$lang.part")
            context.assets.open("tessdata/${file.name}").use { input -> temp.outputStream().use { input.copyTo(it) } }
            check(temp.renameTo(file))
        }
        return TessBaseAPI().apply {
            check(init(root.absolutePath, "eng+rus"))
            pageSegMode = TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT
        }
    }

    private fun bitmap(call: MethodCall): Bitmap {
        val path = call.argument<String>("file")
        if (path != null) return fromFile(path)
        val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
        val width = requireNotNull(call.argument<Int>("width"))
        val height = requireNotNull(call.argument<Int>("height"))
        val jpeg = ByteArrayOutputStream()
        YuvImage(bytes, ImageFormat.NV21, width, height, null).compressToJpeg(Rect(0,0,width,height), 94, jpeg)
        val encoded = jpeg.toByteArray()
        return rotate(BitmapFactory.decodeByteArray(encoded,0,encoded.size), call.argument<Int>("rotation") ?: 0)
    }

    private fun fromFile(path: String): Bitmap {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        options.inSampleSize = Integer.highestOneBit((maxOf(options.outWidth, options.outHeight) / 1600).coerceAtLeast(1))
        options.inJustDecodeBounds = false
        return rotate(requireNotNull(BitmapFactory.decodeFile(path, options)), ExifInterface(path).rotationDegrees)
    }

    private fun rotate(image: Bitmap, degrees: Int): Bitmap {
        if (degrees == 0) return image
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(image,0,0,image.width,image.height,matrix,true).also { if (it !== image) image.recycle() }
    }

    fun close() {
        worker.execute { engine?.recycle(); identifier.close() }
        worker.shutdown()
    }
}
