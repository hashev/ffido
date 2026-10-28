package io.github.hashev.ffido

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class AndroidImageActions(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "org.ffido/images")
    private var generation = 0
    private var pending: MethodChannel.Result? = null
    private val root = File(activity.cacheDir, "image-share")
    // 7421 is document save; 7422 belongs to the updater permission flow.
    companion object { const val requestCode = 7430 }
    init {
        // Never remove a live share on the next invocation. Retain it for 24h.
        Thread { root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() >= 86400000L }?.forEach { it.deleteRecursively() } }.start()
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "openBrowser" -> {
                        val uri = Uri.parse(call.argument<String>("url"))
                        require(uri.scheme in setOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo.isNullOrEmpty())
                        // Resolve a generic URL, then target that browser explicitly:
                        // verified app links must not intercept a message URL.
                        val generic = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.example.com/")).addCategory(Intent.CATEGORY_BROWSABLE)
                        val browsers = activity.packageManager.queryIntentActivities(generic, PackageManager.MATCH_ALL or PackageManager.GET_RESOLVED_FILTER)
                            .filter { it.filter?.countDataAuthorities() == 0 && it.filter?.hasDataScheme("https") == true }
                        val preferred = activity.packageManager.resolveActivity(generic, PackageManager.MATCH_DEFAULT_ONLY)
                        val browser = browsers.firstOrNull { it.activityInfo.packageName == preferred?.activityInfo?.packageName } ?: browsers.firstOrNull()
                        if (browser == null) result.success(false)
                        else {
                            activity.startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE).setPackage(browser.activityInfo.packageName))
                            result.success(true)
                        }
                    }
                    "cancel" -> { generation++; pending?.success("cancelled"); pending = null; result.success(null) }
                    "share" -> {
                        if (pending != null) { result.error("busy", "Отправка уже открыта", null); return@setMethodCallHandler }
                        val bytes = call.argument<ByteArray>("bytes")
                        val mime = call.argument<String>("mime")
                        val name = call.argument<String>("name")
                        require(bytes != null && bytes.isNotEmpty() && bytes.size <= 16 * 1024 * 1024)
                        require(mime in setOf("image/png", "image/jpeg", "image/gif", "image/webp"))
                        require(!name.isNullOrBlank() && name.length <= 200 && name.none { it < ' ' || it in "/\\:*?\"<>|" } && !name.startsWith('.'))
                        pending = result
                        val token = generation
                        Thread {
                            try {
                                val dir = File(root, UUID.randomUUID().toString()).apply { mkdirs() }
                                val file = File(dir, name).apply { writeBytes(bytes) }
                                val uri = FileProvider.getUriForFile(activity, activity.packageName + ".images", file)
                                activity.runOnUiThread {
                                    if (token != generation) return@runOnUiThread
                                    try {
                                        val send = Intent(Intent.ACTION_SEND).apply {
                                            type = mime
                                            putExtra(Intent.EXTRA_STREAM, uri)
                                            clipData = ClipData.newUri(activity.contentResolver, name, uri)
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        }
                                        activity.startActivityForResult(Intent.createChooser(send, "Поделиться изображением"), requestCode)
                                    } catch (error: Exception) { pending = null; result.error("share", "Не удалось открыть отправку", null) }
                                }
                            } catch (error: Exception) { activity.runOnUiThread { if (token == generation) { pending = null; result.error("share", "Не удалось подготовить файл", null) } } }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("image_action", "Действие недоступно", null) }
        }
    }
    fun returned(resultCode: Int) {
        // Chooser result is not proof that another app consumed the bytes.
        pending?.success(if (resultCode == Activity.RESULT_OK) "handedOff" else "cancelled")
        pending = null
    }
    fun detach() { generation++; channel.setMethodCallHandler(null); pending?.success("cancelled"); pending = null }
}
