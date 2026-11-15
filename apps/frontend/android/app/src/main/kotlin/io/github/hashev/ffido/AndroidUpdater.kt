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
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.UUID

class AndroidUpdater(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val execute: (() -> Unit) -> Unit = { Thread(it).start() }
) {
    companion object {
        const val permissionRequest = 7422
        var active: WeakReference<AndroidUpdater>? = null
        private var working: String? = null
        private val operations = Any()
        private val main = Handler(Looper.getMainLooper())

        // Terminal callbacks are claimed on the main thread by operation identity.
        // A stale worker or repeated broadcast cannot complete a newer install.
        internal fun finish(context: Context, operation: String, status: Int?, outcome: String? = null, error: String? = null): Map<String, Any?>? {
            val state = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
            val (fields, path) = synchronized(operations) {
                if (state.getString("operation", null) != operation) return null
                val path = state.getString("path", null)
                saveOutcome(context, status, outcome) to path
            }
            if (path != null) {
                val file = File(path).canonicalFile
                if (file.path.startsWith(context.cacheDir.canonicalPath + File.separator)) file.delete()
            }
            active?.get()?.deliver(fields, error)
            return fields
        }

        @Suppress("DEPRECATION")
        private fun stage(context: Context, file: File, operation: String) {
            val state = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
            try {
                val manager = context.packageManager
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                val candidate = manager.getPackageArchiveInfo(file.path, flags) ?: error("Неверный APK")
                val installed = manager.getPackageInfo(context.packageName, flags)
                fun certificates(info: PackageInfo): Set<String> {
                    val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
                    return signatures.orEmpty().map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } }.toSet()
                }
                val next = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
                val old = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                require(candidate.packageName == context.packageName && next > old) { "Другой пакет или понижение версии" }
                val trusted = certificates(installed)
                require(trusted.isNotEmpty() && certificates(candidate) == trusted) { "Подпись APK отличается от установленной" }
                val installer = manager.packageInstaller
                val fileSize = file.length()
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(context.packageName); setSize(fileSize)
                    if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                }
                // Open before publishing the session: Dart may remove staging after
                // detach, but the worker's descriptor must remain readable.
                file.inputStream().use { input ->
                    val id = synchronized(operations) {
                        if (state.getString("operation", null) != operation) return
                        val created = installer.createSession(params)
                        state.edit().putInt("session", created).putLong("targetVersion", next)
                            .putBoolean("submitted", false).putString("outcome", "pending").commit()
                        created
                    }
                    installer.openSession(id).use { session ->
                        try {
                            session.openWrite("base.apk", 0, fileSize).use { output -> input.copyTo(output); session.fsync(output) }
                            val intent = Intent(context, UpdateStatusReceiver::class.java)
                            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                            synchronized(operations) {
                                session.commit(PendingIntent.getBroadcast(context, id, intent, flags).intentSender)
                                state.edit().putBoolean("submitted", true).commit()
                            }
                        } catch (error: Exception) { session.abandon(); throw error }
                    }
                }
            } catch (error: Exception) {
                // Only validation errors are suitable for display; I/O paths are private.
                val safe = when (error.message) {
                    "Другой пакет или понижение версии", "Подпись APK отличается от установленной", "Неверный APK" -> error.message
                    else -> "Не удалось подготовить установку"
                }
                main.post { finish(context, operation, PackageInstaller.STATUS_FAILURE, error = safe) }
            } finally {
                main.post { if (working == operation) working = null }
            }
        }
    }
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "ffido/updates")
    private val state = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
    private var pending: MethodChannel.Result? = null
    private var operationId: String? = null
    private var reported: Map<String, Any?>? = null
    private var attached = true
    init {
        active = WeakReference(this)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf("sdk" to Build.VERSION.SDK_INT, "cacheDirectory" to context.cacheDir.canonicalPath))
                "recover" -> result.success(recover())
                "install" -> {
                    if (pending != null || recover()?.get("outcome") == "pending") { result.error("busy", "Установка уже выполняется", null); return@setMethodCallHandler }
                    try {
                        val file = File(call.argument<String>("path") ?: error("Не указан APK")).canonicalFile
                        require(file.isFile && file.extension == "apk" && file.length() in 1..(2L * 1024 * 1024 * 1024)) { "Неверный APK" }
                        require(file.path.startsWith(context.cacheDir.canonicalPath + File.separator)) { "APK должен находиться в закрытом кеше приложения" }
                        val operation = UUID.randomUUID().toString()
                        state.edit().clear().putString("operation", operation).putString("path", file.path).putString("outcome", "preparing").commit()
                        operationId = operation
                        pending = result
                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
                            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")), permissionRequest)
                        } else submit()
                    } catch (_: Exception) {
                        val operation = state.getString("operation", null)
                        if (pending === result && operation != null) finish(context, operation, PackageInstaller.STATUS_FAILURE, error = "Не удалось подготовить установку")
                        else result.error("install", "Не удалось подготовить установку", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun permissionReturned() {
        if (!attached || pending == null || state.getString("outcome", null) != "preparing") return
        if (Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls()) submit()
        else state.getString("operation", null)?.let { finish(context, it, PackageInstaller.STATUS_FAILURE_ABORTED, "permission_denied") }
    }
    private fun deliver(fields: Map<String, Any?>, error: String?) {
        if (!attached) return
        val result = pending
        pending = null; operationId = null
        if (result != null) {
            reported = fields
            if (error != null) result.error("install", error, fields) else result.success(fields)
        } else if (reported != fields) {
            reported = fields
            channel.invokeMethod("installResult", fields)
        }
    }
    private fun recovered(fields: Map<String, Any?>): Map<String, Any?>? {
        if (pending != null) {
            deliver(fields, null)
            return null
        }
        if (reported == fields) return null
        reported = fields
        return fields
    }
    @Suppress("DEPRECATION")
    private fun recover(): Map<String, Any?>? {
        val outcome = state.getString("outcome", null) ?: return null
        if (outcome == "pending" || outcome == "preparing") {
            val installed = context.packageManager.getPackageInfo(context.packageName, 0)
            val version = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
            val target = state.getLong("targetVersion", -1)
            val operation = state.getString("operation", null)
            if (target > 0 && version == target) {
                if (operation != null) { finish(context, operation, PackageInstaller.STATUS_SUCCESS); return null }
                return recovered(saveOutcome(context, PackageInstaller.STATUS_SUCCESS))
            }
            val session = state.getInt("session", -1)
            if (pending != null || (operation != null && working == operation)) {
                return mapOf("outcome" to "pending", "status" to null)
            }
            if (session >= 0 && context.packageManager.packageInstaller.getSessionInfo(session) != null) {
                if (operation == null || state.getBoolean("submitted", false))
                    return mapOf("outcome" to "pending", "status" to null)
                // A dead process cannot finish copying an unsubmitted session.
                try { context.packageManager.packageInstaller.abandonSession(session) }
                catch (_: Exception) { /* A commit racing process death may already be sealed. */ }
            }
            // Missing session/callback is not proof of an antivirus rejection.
            if (operation != null) { finish(context, operation, null, "unknown"); return null }
            return recovered(saveOutcome(context, null, "unknown"))
        }
        return recovered(mapOf("outcome" to outcome, "status" to if (state.contains("status")) state.getInt("status", 0) else null))
    }
    fun detach() {
        if (!attached) return
        attached = false
        val current = active?.get()
        if (current === this) active = null
        if (current == null || current === this || current.messenger !== messenger)
            channel.setMethodCallHandler(null)
        val result = pending
        pending = null
        val operation = operationId
        operationId = null
        val cancelled = synchronized(operations) {
            if (result != null && operation != null && state.getString("operation", null) == operation &&
                state.getString("outcome", null) == "preparing") {
                // Cancellation wins before any session is published; a queued
                // worker checks identity and cannot resurrect this operation.
                finish(context, operation, PackageInstaller.STATUS_FAILURE_ABORTED)
            } else null
        }
        if (cancelled != null) result?.success(cancelled)
        else result?.error("detached", "Окно закрыто; результат установки доступен после восстановления", null)
    }
    private fun submit() {
        val operation = state.getString("operation", null) ?: return
        if (working == operation || state.getString("outcome", null) != "preparing") return
        val file = File(state.getString("path", null) ?: return)
        working = operation
        // The worker owns application context and operation identity, never Activity.
        val application = context
        execute { stage(application, file, operation) }
    }
}

class UpdateStatusReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        val state = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
        val session = state.getInt("session", -1)
        if (session < 0 || intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -2) != session) return
        val operation = state.getString("operation", null)
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        fun finish(status: Int) {
            if (operation != null) AndroidUpdater.finish(context, operation, status)
            else saveOutcome(context, status)
        }
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmation = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                else intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            try {
                requireNotNull(confirmation)
                context.startActivity(confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) { finish(PackageInstaller.STATUS_FAILURE) }
        } else finish(status)
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
        .remove("session").remove("targetVersion").remove("submitted").remove("path").remove("operation").putString("outcome", outcome)
    if (status == null) edit.remove("status") else edit.putInt("status", status)
    edit.commit()
    return mapOf("outcome" to outcome, "status" to status)
}
