package io.github.hashev.ffido

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.security.MessageDigest

class AndroidUpdater(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val permissionRequest = 7422
        var active: WeakReference<AndroidUpdater>? = null
    }
    private var pending: MethodChannel.Result? = null
    private var apk: File? = null
    init {
        active = WeakReference(this)
        MethodChannel(messenger, "ffido/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf("sdk" to Build.VERSION.SDK_INT, "cacheDirectory" to activity.cacheDir.canonicalPath))
                "install" -> {
                    if (pending != null) { result.error("busy", "Установка уже выполняется", null); return@setMethodCallHandler }
                    try {
                        val file = File(call.argument<String>("path") ?: error("Не указан APK")).canonicalFile
                        require(file.isFile && file.extension == "apk" && file.length() in 1..(2L * 1024 * 1024 * 1024)) { "Неверный APK" }
                        require(file.path.startsWith(activity.cacheDir.canonicalPath + File.separator)) { "APK должен находиться в закрытом кеше приложения" }
                        apk = file; pending = result
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")), permissionRequest)
                        } else submit()
                    } catch (error: Exception) { apk = null; pending = null; result.error("install", error.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun permissionReturned() {
        if (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()) submit()
        else complete(PackageInstaller.STATUS_FAILURE_ABORTED)
    }
    fun complete(status: Int) {
        val result = pending ?: return
        pending = null; apk?.delete(); apk = null
        when (status) {
            PackageInstaller.STATUS_SUCCESS -> result.success(true)
            PackageInstaller.STATUS_FAILURE_ABORTED -> result.success(false)
            else -> result.error("install", "Система отклонила обновление (код $status)", null)
        }
    }
    @Suppress("DEPRECATION")
    private fun submit() {
        val file = apk ?: return
        Thread {
            try {
                val manager = activity.packageManager
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                val candidate = manager.getPackageArchiveInfo(file.path, flags) ?: error("Неверный APK")
                val installed = manager.getPackageInfo(activity.packageName, flags)
                fun certificates(info: PackageInfo): Set<String> {
                    val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
                    return signatures.orEmpty().map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } }.toSet()
                }
                val next = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
                val old = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                require(candidate.packageName == activity.packageName && next > old) { "Другой пакет или понижение версии" }
                val trusted = certificates(installed)
                require(trusted.isNotEmpty() && certificates(candidate) == trusted) { "Подпись APK отличается от установленной" }
                val installer = manager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(activity.packageName); setSize(file.length())
                    if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                }
                val id = installer.createSession(params)
                installer.openSession(id).use { session ->
                    try {
                        file.inputStream().use { input -> session.openWrite("base.apk", 0, file.length()).use { output -> input.copyTo(output); session.fsync(output) } }
                        val intent = Intent(activity, UpdateStatusReceiver::class.java)
                        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                        session.commit(PendingIntent.getBroadcast(activity, id, intent, flags).intentSender)
                    } catch (error: Exception) { session.abandon(); throw error }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    val result = pending
                    pending = null; apk?.delete(); apk = null
                    result?.error("install", error.message ?: "Не удалось подготовить установку", null)
                }
            }
        }.start()
    }
}

class UpdateStatusReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmation = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                else intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (confirmation == null) AndroidUpdater.active?.get()?.complete(PackageInstaller.STATUS_FAILURE)
            else try { context.startActivity(confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                 catch (_: Exception) { AndroidUpdater.active?.get()?.complete(PackageInstaller.STATUS_FAILURE) }
        } else AndroidUpdater.active?.get()?.complete(status)
    }
}
