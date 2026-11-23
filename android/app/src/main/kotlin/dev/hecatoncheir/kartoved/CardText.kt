package dev.hecatoncheir.kartoved

import android.content.Context
import android.graphics.*
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class CardText(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val identifier = LanguageIdentification.getClient()
    private var engine: TessBaseAPI? = null

    fun read(call: MethodCall, reply: MethodChannel.Result) {
        worker.execute {
            val result = runCatching { recognize(bitmap(call)) }.getOrNull()
            android.os.Handler(context.mainLooper).post { reply.success(result) }
        }
    }

    private fun recognize(bitmap: Bitmap): Map<String, String> {
        val api = engine ?: open().also { engine = it }
        try {
            api.setImage(bitmap)
            val text = api.getUTF8Text().orEmpty()
            val language = Tasks.await(identifier.identifyLanguage(text))
            return mapOf("text" to text, "language" to language)
        } finally {
            api.clear()
            bitmap.recycle()
        }
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
