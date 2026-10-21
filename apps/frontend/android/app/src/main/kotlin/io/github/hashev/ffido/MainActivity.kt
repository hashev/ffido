package io.github.hashev.ffido

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var updater: AndroidUpdater? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private val saveRequest = 7421

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updater = AndroidUpdater(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.ffido/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveUue") { result.notImplemented(); return@setMethodCallHandler }
                if (pendingResult != null) { result.error("busy", "Сохранение уже открыто", null); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")?.substringAfterLast('/')?.substringAfterLast('\\')
                if (bytes == null || bytes.size > 16 * 1024 * 1024 || name.isNullOrBlank()) {
                    result.error("invalid", "Неверный файл", null); return@setMethodCallHandler
                }
                pendingBytes = bytes
                pendingResult = result
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    startActivityForResult(intent, saveRequest)
                } catch (error: Exception) {
                    pendingBytes = null; pendingResult = null
                    result.error("save", "Не удалось открыть системное сохранение", null)
                }
            }
    }

    @Deprecated("Android callback retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == AndroidUpdater.permissionRequest) { updater?.permissionReturned(); return }
        if (requestCode != saveRequest) { super.onActivityResult(requestCode, resultCode, data); return }
        val result = pendingResult ?: return
        val bytes = pendingBytes
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            pendingResult = null; pendingBytes = null; result.success(false); return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w")?.use { stream -> stream.write(bytes); stream.flush() }
                    ?: throw IllegalStateException("No output stream")
                runOnUiThread { pendingResult = null; pendingBytes = null; result.success(true) }
            } catch (error: Exception) {
                runOnUiThread { pendingResult = null; pendingBytes = null; result.error("save", "Не удалось сохранить файл", null) }
            }
        }.start()
    }
}
