package io.github.hashev.ffido

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class AndroidFileSaver(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val execute: (() -> Unit) -> Unit = { Thread(it).start() }
) {
    companion object {
        const val requestCode = 7421
        private var active: WeakReference<AndroidFileSaver>? = null
    }
    private val channel = MethodChannel(messenger, "org.ffido/files")
    private val resolver = activity.applicationContext.contentResolver
    private var pending: MethodChannel.Result? = null
    private var bytes: ByteArray? = null
    private var writing = false
    private var attached = true
    init {
        active = WeakReference(this)
        channel.setMethodCallHandler { call, result ->
            if (call.method != "saveUue") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("busy", "Сохранение уже открыто", null); return@setMethodCallHandler }
            val data = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("name")?.substringAfterLast('/')?.substringAfterLast('\\')
            if (data == null || data.size > 16 * 1024 * 1024 || name.isNullOrBlank()) {
                result.error("invalid", "Неверный файл", null); return@setMethodCallHandler
            }
            bytes = data; pending = result
            try {
                activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, name)
                }, requestCode)
            } catch (_: Exception) { complete(result, null, "Не удалось открыть системное сохранение") }
        }
    }
    fun returned(resultCode: Int, intent: Intent?) {
        val result = pending ?: return
        if (!attached || writing) return
        val data = bytes
        val uri = intent?.data
        if (resultCode != Activity.RESULT_OK || uri == null || data == null) {
            complete(result, false); return
        }
        writing = true
        val output = resolver
        val main = Handler(Looper.getMainLooper())
        val owner = WeakReference(this)
        execute {
            val error = try {
                output.openOutputStream(uri, "w")?.use { stream -> stream.write(data); stream.flush() }
                    ?: throw IllegalStateException("No output stream")
                null
            } catch (_: Exception) { "Не удалось сохранить файл" }
            main.post { owner.get()?.complete(result, error == null, error) }
        }
    }
    private fun complete(result: MethodChannel.Result, success: Boolean?, error: String? = null) {
        // A detached window has already completed this result. Never touch a
        // subsequent request when an older write finishes on the main queue.
        if (pending !== result) return
        pending = null; bytes = null; writing = false
        if (error != null) result.error("save", error, null) else result.success(success)
    }
    fun detach() {
        if (!attached) return
        attached = false
        val current = active?.get()
        if (current === this) active = null
        if (current == null || current === this || current.messenger !== messenger)
            channel.setMethodCallHandler(null)
        val result = pending
        pending = null; bytes = null
        result?.error("detached", "Окно закрыто во время сохранения файла", null)
    }
}
