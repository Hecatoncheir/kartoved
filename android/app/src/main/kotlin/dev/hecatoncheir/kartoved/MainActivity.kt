package dev.hecatoncheir.kartoved

import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val textReader by lazy { CardText(applicationContext) }
    private var chime: ScanChime? = null
    private val documents by lazy { Documents(this) }
    private val settings by lazy { getSharedPreferences("scanner", MODE_PRIVATE) }
    private val interfaceSettings by lazy { getSharedPreferences("interface", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeControlStream = AudioManager.STREAM_MUSIC
        chime?.close()
        chime = runCatching { ScanChime(applicationContext) }.getOrNull()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kartoved/android")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "readText" -> textReader.read(call, reply)
                    "scanPhoto" -> textReader.photo(call, reply)
                    "warmTray" -> textReader.warmTray(reply)
                    "trayPhoto" -> textReader.trayPhoto(call, reply)
                    "readTrayText" -> textReader.readTrayText(call, reply)
                    "interfaceLanguage" -> {
                        val code = call.arguments as? String
                        if (code != null) interfaceSettings.edit().putString("language", code).apply()
                        reply.success(code ?: interfaceSettings.getString("language", null))
                    }
                    "scannerGuide" -> {
                        val visible = call.arguments as? Boolean
                        if (visible != null) settings.edit().putBoolean("guide", visible).apply()
                        reply.success(visible ?: settings.getBoolean("guide", true))
                    }
                    "scannerModel" -> {
                        val model = call.arguments as? String
                        if (model != null) settings.edit().putString("recognitionModel", model).apply()
                        reply.success(model ?: settings.getString("recognitionModel", null))
                    }
                    "scannerTray" -> {
                        val tray = call.arguments as? Boolean
                        if (tray != null) settings.edit().putBoolean("tray", tray).apply()
                        reply.success(tray ?: settings.getBoolean("tray", true))
                    }
                    "scannerProfile" -> {
                        val profile = call.arguments as? String
                        if (profile != null) settings.edit().putString("profile", profile).apply()
                        reply.success(profile ?: settings.getString("profile", null) ?:
                            if (settings.getBoolean("tray", true)) "tray" else "automatic")
                    }
                    "scannerOption" -> {
                        val key = requireNotNull(call.argument<String>("name"))
                        val value = call.argument<Boolean>("value")
                        if (value != null) settings.edit().putBoolean(key, value).apply()
                        reply.success(value ?: settings.getBoolean(key, false))
                    }
                    "chime" -> {
                        chime?.play(call.arguments as? String)
                        reply.success(null)
                    }
                    "openScryfall" -> reply.success(openScryfall(call.arguments as? String))
                    "saveCsv" -> documents.saveCsv(call.argument("name"), call.argument("csv"), reply)
                    "saveBackup" -> documents.saveBackup(call.argument("name"), call.argument("path"), reply)
                    "openBackup" -> documents.openBackup(call.argument("path"), reply)
                    else -> reply.notImplemented()
                }
            }
    }

    private fun openScryfall(url: String?): Boolean {
        val page = url?.let(Uri::parse) ?: return false
        if (page.scheme != "https" || page.host != "scryfall.com") return false
        return runCatching { startActivity(Intent(Intent.ACTION_VIEW, page)) }.isSuccess
    }

    @Deprecated("Используется механизм результата FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        documents.finish(requestCode, resultCode, data?.data)
    }

    override fun onDestroy() {
        textReader.close()
        chime?.close()
        chime = null
        super.onDestroy()
    }
}
