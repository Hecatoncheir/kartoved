package dev.hecatoncheir.kartoved

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val textReader by lazy { CardText(applicationContext) }
    private var player: MediaPlayer? = null
    private var pending: Pair<String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kartoved/android")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "readText" -> textReader.read(call, reply)
                    "chime" -> {
                        runCatching {
                            if (player == null) player = MediaPlayer.create(this, R.raw.card_added)
                            player?.seekTo(0)
                            player?.start()
                        }
                        reply.success(null)
                    }
                    "saveCsv" -> chooseDocument(call, reply)
                    else -> reply.notImplemented()
                }
            }
    }

    private fun chooseDocument(call: MethodCall, reply: MethodChannel.Result) {
        val csv = call.argument<String>("csv")
        if (csv == null || pending != null) {
            reply.error("export", "Экспорт недоступен", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/csv"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
        }
        pending = csv to reply
        try {
            startActivityForResult(intent, 4308)
        } catch (error: Exception) {
            pending = null
            reply.error("export", error.localizedMessage, null)
        }
    }

    @Deprecated("Используется механизм результата FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4308) return
        val (csv, reply) = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(false)
            return
        }
        Thread {
            val saved = runCatching {
                val stream = requireNotNull(contentResolver.openOutputStream(uri, "wt"))
                stream.bufferedWriter(Charsets.UTF_8).use { it.write(csv) }
            }
            runOnUiThread { saved.fold({ reply.success(true) }, { reply.error("export", it.localizedMessage, null) }) }
        }.start()
    }

    override fun onDestroy() {
        textReader.close()
        player?.release()
        player = null
        super.onDestroy()
    }
}
