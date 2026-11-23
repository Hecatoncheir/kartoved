package dev.hecatoncheir.kartoved

import android.content.Intent
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val textReader by lazy { CardText(applicationContext) }
    private var player: MediaPlayer? = null
    private val documents by lazy { Documents(this) }

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
                    "saveCsv" -> documents.saveCsv(call.argument("name"), call.argument("csv"), reply)
                    "saveBackup" -> documents.saveBackup(call.argument("name"), call.argument("path"), reply)
                    "openBackup" -> documents.openBackup(call.argument("path"), reply)
                    else -> reply.notImplemented()
                }
            }
    }

    @Deprecated("Используется механизм результата FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        documents.finish(requestCode, resultCode, data?.data)
    }

    override fun onDestroy() {
        textReader.close()
        player?.release()
        player = null
        super.onDestroy()
    }
}
