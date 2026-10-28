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
    private val channel = MethodChannel(messenger, "ffido/updates")
    private val state = activity.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
    private var pending: MethodChannel.Result? = null
    private var apk: File? = null
    init {
        active = WeakReference(this)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf("sdk" to Build.VERSION.SDK_INT, "cacheDirectory" to activity.cacheDir.canonicalPath))
                "recover" -> result.success(recover())
                "install" -> {
                    if (pending != null || recover()?.get("outcome") == "pending") { result.error("busy", "Установка уже выполняется", null); return@setMethodCallHandler }
                    try {
                        val file = File(call.argument<String>("path") ?: error("Не указан APK")).canonicalFile
                        require(file.isFile && file.extension == "apk" && file.length() in 1..(2L * 1024 * 1024 * 1024)) { "Неверный APK" }
                        require(file.path.startsWith(activity.cacheDir.canonicalPath + File.separator)) { "APK должен находиться в закрытом кеше приложения" }
                        state.edit().clear().putString("outcome", "preparing").commit()
                        apk = file; pending = result
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")), permissionRequest)
                        } else submit()
                    } catch (error: Exception) {
                        apk = null; pending = null
                        saveOutcome(activity, PackageInstaller.STATUS_FAILURE)
                        result.error("install", "Не удалось подготовить установку", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun permissionReturned() {
        if (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()) submit()
        else complete(PackageInstaller.STATUS_FAILURE_ABORTED, "permission_denied")
    }
    fun complete(status: Int, outcome: String? = null) {
        val fields = saveOutcome(activity, status, outcome)
        val result = pending
        pending = null; apk?.delete(); apk = null
        if (result != null) result.success(fields)
        else channel.invokeMethod("installResult", fields)
    }
    @Suppress("DEPRECATION")
    private fun recover(): Map<String, Any?>? {
        val outcome = state.getString("outcome", null) ?: return null
        if (outcome == "pending" || outcome == "preparing") {
            val installed = activity.packageManager.getPackageInfo(activity.packageName, 0)
            val version = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
            val target = state.getLong("targetVersion", -1)
            if (target > 0 && version == target) return saveOutcome(activity, PackageInstaller.STATUS_SUCCESS)
            val session = state.getInt("session", -1)
            if (pending != null || (session >= 0 && activity.packageManager.packageInstaller.getSessionInfo(session) != null)) {
                return mapOf("outcome" to "pending", "status" to null)
            }
            // Missing session/callback is not proof of an antivirus rejection.
            return saveOutcome(activity, null, "unknown")
        }
        return mapOf("outcome" to outcome, "status" to if (state.contains("status")) state.getInt("status", 0) else null)
    }
    fun detach() {
        if (active?.get() === this) active = null
        pending = null
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
                state.edit().putInt("session", id).putLong("targetVersion", next).putString("outcome", "pending").commit()
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
                    saveOutcome(activity, PackageInstaller.STATUS_FAILURE)
                    // Only our validation errors are suitable for display; I/O paths are private.
                    val safe = when (error.message) {
                        "Другой пакет или понижение версии", "Подпись APK отличается от установленной", "Неверный APK" -> error.message
                        else -> "Не удалось подготовить установку"
                    }
                    result?.error("install", safe, mapOf("outcome" to "failed", "status" to PackageInstaller.STATUS_FAILURE))
                }
            }
        }.start()
    }
}

class UpdateStatusReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        val state = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
        val session = state.getInt("session", -1)
        if (session < 0 || intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -2) != session) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmation = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                else intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            try {
                requireNotNull(confirmation)
                context.startActivity(confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) {
                saveOutcome(context, PackageInstaller.STATUS_FAILURE)
                AndroidUpdater.active?.get()?.complete(PackageInstaller.STATUS_FAILURE)
            }
        } else {
            saveOutcome(context, status)
            AndroidUpdater.active?.get()?.complete(status)
        }
    }
}

// Persist only a bounded outcome and numeric OS status, never raw system messages.
private fun saveOutcome(context: Context, status: Int?, explicit: String? = null): Map<String, Any?> {
    val outcome = explicit ?: when (status) {
        PackageInstaller.STATUS_SUCCESS -> "success"
        PackageInstaller.STATUS_FAILURE_ABORTED -> "cancelled"
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
        else -> "failed"
    }
    val edit = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE).edit()
        .remove("session").remove("targetVersion").putString("outcome", outcome)
    if (status == null) edit.remove("status") else edit.putInt("status", status)
    edit.commit()
    return mapOf("outcome" to outcome, "status" to status)
}
