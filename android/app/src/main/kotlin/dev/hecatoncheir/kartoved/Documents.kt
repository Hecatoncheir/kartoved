package dev.hecatoncheir.kartoved

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.OutputStream

class Documents(private val activity: Activity) {
    private data class Request(val reply: MethodChannel.Result, val copy: (Uri) -> Unit)
    private var pending: Request? = null
    private val resolver get() = activity.contentResolver

    fun saveCsv(name: String?, csv: String?, reply: MethodChannel.Result) {
        if (csv == null) return reply.error("export", "Экспорт недоступен", null)
        save(name, "text/csv", reply) { output ->
            output.bufferedWriter(Charsets.UTF_8).use { it.write(csv) }
        }
    }

    fun saveBackup(name: String?, path: String?, reply: MethodChannel.Result) {
        if (path == null) return reply.error("document", "Файл не указан", null)
        save(name, "application/json", reply) { output ->
            File(path).inputStream().use { it.copyTo(output) }
        }
    }

    private fun save(name: String?, mime: String, reply: MethodChannel.Result, write: (OutputStream) -> Unit) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).setType(mime)
            .putExtra(Intent.EXTRA_TITLE, name)
        choose(intent, reply) { uri ->
            requireNotNull(resolver.openOutputStream(uri, "wt")).use(write)
        }
    }

    fun openBackup(path: String?, reply: MethodChannel.Result) {
        if (path == null) return reply.error("document", "Файл не указан", null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
        choose(intent, reply) { uri ->
            requireNotNull(resolver.openInputStream(uri)).use { input ->
                File(path).outputStream().use { output -> input.copyTo(output) }
            }
        }
    }

    private fun choose(intent: Intent, reply: MethodChannel.Result, copy: (Uri) -> Unit) {
        if (pending != null) {
            reply.error("document", "Сначала завершите выбор файла", null)
            return
        }
        pending = Request(reply, copy)
        try {
            activity.startActivityForResult(intent.addCategory(Intent.CATEGORY_OPENABLE), 4308)
        } catch (error: Exception) {
            pending = null
            reply.error("document", error.localizedMessage, null)
        }
    }

    fun finish(requestCode: Int, resultCode: Int, uri: Uri?) {
        if (requestCode != 4308) return
        val request = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || uri == null) {
            request.reply.success(false)
            return
        }
        Thread {
            val result = runCatching { request.copy(uri) }
            activity.runOnUiThread {
                result.fold({ request.reply.success(true) }, {
                    request.reply.error("document", it.localizedMessage, null)
                })
            }
        }.start()
    }
}
