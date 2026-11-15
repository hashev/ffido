@file:Suppress("DEPRECATION")
package io.github.hashev.ffido

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.provider.MediaStore
import android.test.InstrumentationTestCase
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID

class NativeLifecycleTest : InstrumentationTestCase() {
    private lateinit var activity: LifecycleTestActivity
    private val outputs = mutableListOf<Uri>()
    private val codec = StandardMethodCodec.INSTANCE
    private class Reply { var count = 0; var value: Any? = null; var error: String? = null }
    private inner class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        val events = mutableListOf<MethodCall>()
        override fun send(channel: String, message: ByteBuffer?) { send(channel, message, null) }
        override fun send(channel: String, message: ByteBuffer?, reply: BinaryMessenger.BinaryReply?) {
            if (message != null) { message.flip(); events.add(codec.decodeMethodCall(message)) }
            reply?.reply(null)
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        fun call(channel: String, name: String, arguments: Any? = null): Reply {
            val result = Reply()
            val message = codec.encodeMethodCall(MethodCall(name, arguments)); message.flip()
            handlers.getValue(channel).onMessage(message) { envelope ->
                result.count++
                envelope?.flip()
                try { result.value = codec.decodeEnvelope(requireNotNull(envelope)) }
                catch (error: FlutterException) { result.error = error.code }
            }
            return result
        }
    }
    private fun ui(block: () -> Unit) { instrumentation.runOnMainSync(block) }
    private fun await(condition: () -> Boolean) {
        repeat(150) {
            instrumentation.waitForIdleSync()
            if (condition()) return
            Thread.sleep(20)
        }
        fail("Lifecycle condition timed out")
    }
    override fun setUp() {
        super.setUp()
        val context = instrumentation.targetContext
        context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE).edit().clear().commit()
        activity = instrumentation.startActivitySync(Intent(context, LifecycleTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as LifecycleTestActivity
    }
    @Deprecated("SDK instrumentation lifecycle")
    override fun tearDown() {
        ui { activity.finish() }
        instrumentation.waitForIdleSync()
        for (uri in outputs) instrumentation.targetContext.contentResolver.delete(uri, null, null)
        super.tearDown()
    }
    private fun recreate() {
        val old = activity
        ui { old.recreate() }
        await { LifecycleTestActivity.current?.get()?.let { it !== old } == true }
        activity = LifecycleTestActivity.current!!.get()!!
    }
    private fun permission(allowed: Boolean) {
        instrumentation.uiAutomation.executeShellCommand("appops set ${activity.packageName} REQUEST_INSTALL_PACKAGES ${if (allowed) "allow" else "deny"}")
            .use { descriptor -> android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).readBytes() }
    }
    private fun apk() = File(activity.cacheDir, "lifecycle-${UUID.randomUUID()}.apk").apply { writeText("synthetic invalid APK") }
    private fun updater(messenger: Messenger, jobs: MutableList<() -> Unit>) {
        ui { activity.updater = AndroidUpdater(activity, messenger) { jobs.add(it) } }
    }
    private fun install(messenger: Messenger, file: File): Reply {
        var reply: Reply? = null
        ui { reply = messenger.call("ffido/updates", "install", mapOf("path" to file.path)) }
        return reply!!
    }
    fun testOldDetachClearsItsMessengerWithoutRemovingTheNewHandler() {
        val jobs = mutableListOf<() -> Unit>(); val oldMessenger = Messenger(); updater(oldMessenger, jobs)
        val old = activity.updater!!; val fresh = Messenger(); updater(fresh, jobs)
        ui {
            old.detach()
            assertFalse(oldMessenger.handlers.containsKey("ffido/updates"))
            assertTrue(fresh.handlers.containsKey("ffido/updates"))
            val shared = Messenger()
            val first = AndroidUpdater(activity, shared)
            val second = AndroidUpdater(activity, shared)
            first.detach()
            assertTrue(shared.handlers.containsKey("ffido/updates"))
            second.detach()
            assertFalse(shared.handlers.containsKey("ffido/updates"))
            val firstSaver = AndroidFileSaver(activity, shared)
            val secondSaver = AndroidFileSaver(activity, shared)
            firstSaver.detach()
            assertTrue(shared.handlers.containsKey("org.ffido/files"))
            secondSaver.detach()
            assertFalse(shared.handlers.containsKey("org.ffido/files"))
        }
    }
    fun testPermissionDenialAndDuplicateCallbackCompleteExactlyOnce() {
        permission(false)
        val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>()
        updater(messenger, jobs)
        val file = apk(); val reply = install(messenger, file)
        assertEquals(0, reply.count); assertEquals(1, activity.requests)
        ui { activity.updater!!.permissionReturned(); activity.updater!!.permissionReturned() }
        assertEquals(1, reply.count)
        assertEquals("permission_denied", (reply.value as Map<*, *>)["outcome"])
        assertTrue(jobs.isEmpty()); assertFalse(file.exists()); assertTrue(messenger.events.isEmpty())
    }
    fun testRecreationDuringPermissionWaitCancelsOnceAndOldCallbackIsIgnored() {
        permission(false)
        val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>()
        updater(messenger, jobs)
        val old = activity.updater!!; val file = apk(); val reply = install(messenger, file)
        recreate()
        ui { old.detach(); old.permissionReturned() }
        assertEquals(1, reply.count); assertEquals("cancelled", (reply.value as Map<*, *>)["outcome"])
        assertTrue(jobs.isEmpty()); assertFalse(file.exists())
        val fresh = Messenger(); updater(fresh, jobs)
        ui { assertEquals("cancelled", (fresh.call("ffido/updates", "recover").value as Map<*, *>)["outcome"]) }
    }
    fun testWorkerOutlivesActivityWithoutCompletingOldResultTwice() {
        permission(true)
        val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>()
        updater(messenger, jobs)
        val file = apk(); val reply = install(messenger, file)
        assertEquals(1, jobs.size)
        ui { activity.updater!!.permissionReturned() }
        assertEquals(1, jobs.size)
        recreate()
        assertEquals(1, reply.count); assertEquals("cancelled", (reply.value as Map<*, *>)["outcome"])
        assertFalse(file.exists())
        val fresh = Messenger(); updater(fresh, jobs)
        val nextFile = apk(); val next = install(fresh, nextFile)
        ui { assertEquals("pending", (fresh.call("ffido/updates", "recover").value as Map<*, *>)["outcome"]) }
        Thread(jobs.removeAt(0)).apply { start(); join() }; instrumentation.waitForIdleSync()
        assertEquals(0, next.count); assertTrue(fresh.events.isEmpty())
        Thread(jobs.removeAt(0)).apply { start(); join() }; await { next.count == 1 }
        assertEquals(1, reply.count); assertEquals("install", next.error)
        assertTrue(fresh.events.isEmpty()); assertFalse(nextFile.exists())
    }

    fun testSessionRecoveryAndRepeatedTerminalBroadcastAfterRecreation() {
        val context = instrumentation.targetContext
        val installer = context.packageManager.packageInstaller
        val session = installer.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL))
        try {
            val file = apk()
            val state = context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE)
            state.edit().putString("operation", UUID.randomUUID().toString()).putString("path", file.path)
                .putString("outcome", "pending").putBoolean("submitted", true).putInt("session", session).commit()
            val jobs = mutableListOf<() -> Unit>(); val messenger = Messenger(); updater(messenger, jobs)
            ui { assertEquals("pending", (messenger.call("ffido/updates", "recover").value as Map<*, *>)["outcome"]) }
            recreate()
            val fresh = Messenger(); updater(fresh, jobs)
            ui {
                assertEquals("pending", (fresh.call("ffido/updates", "recover").value as Map<*, *>)["outcome"])
                val receiver = UpdateStatusReceiver()
                val intent = Intent().putExtra(PackageInstaller.EXTRA_SESSION_ID, session)
                    .putExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE_ABORTED)
                receiver.onReceive(context, Intent(intent).putExtra(PackageInstaller.EXTRA_SESSION_ID, session + 1))
                assertTrue(fresh.events.isEmpty())
                receiver.onReceive(context, intent); receiver.onReceive(context, intent)
                assertEquals(1, fresh.events.size)
                assertEquals("cancelled", (fresh.events.single().arguments as Map<*, *>)["outcome"])
                assertNull(fresh.call("ffido/updates", "recover").value)
                assertEquals(1, fresh.events.size)
            }
            assertFalse(file.exists())
        } finally { installer.abandonSession(session) }
    }
    fun testUnsubmittedSessionAfterProcessLossIsAbandonedAndReportedUnknown() {
        val context = instrumentation.targetContext
        val installer = context.packageManager.packageInstaller
        val session = installer.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL))
        val file = apk()
        context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE).edit()
            .putString("operation", UUID.randomUUID().toString()).putString("path", file.path)
            .putString("outcome", "pending").putBoolean("submitted", false).putInt("session", session).commit()
        val messenger = Messenger(); updater(messenger, mutableListOf())
        ui { assertNull(messenger.call("ffido/updates", "recover").value) }
        assertNull(installer.getSessionInfo(session)); assertFalse(file.exists())
        assertEquals(1, messenger.events.size)
        assertEquals("unknown", (messenger.events.single().arguments as Map<*, *>)["outcome"])
        ui { assertNull(messenger.call("ffido/updates", "recover").value) }
        assertEquals(1, messenger.events.size)
    }
    fun testSubmittedSessionDetachesOldResultOnceAndRecoversIntoNewWindow() {
        permission(true)
        val context = instrumentation.targetContext
        val installer = context.packageManager.packageInstaller
        val session = installer.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL))
        try {
            val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>(); updater(messenger, jobs)
            val file = apk(); val reply = install(messenger, file)
            context.getSharedPreferences("ffido_installer", Context.MODE_PRIVATE).edit()
                .putInt("session", session).putBoolean("submitted", true).putString("outcome", "pending").commit()
            recreate()
            assertEquals(1, reply.count); assertEquals("detached", reply.error); assertTrue(file.exists())
            val fresh = Messenger(); updater(fresh, jobs)
            ui {
                UpdateStatusReceiver().onReceive(context, Intent().putExtra(PackageInstaller.EXTRA_SESSION_ID, session)
                    .putExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE_ABORTED))
            }
            assertEquals(1, fresh.events.size); assertFalse(file.exists())
            Thread(jobs.removeAt(0)).apply { start(); join() }; instrumentation.waitForIdleSync()
            assertEquals(1, fresh.events.size); assertEquals(1, reply.count)
        } finally { installer.abandonSession(session) }
    }
    private fun output(): Uri {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "ffido-lifecycle-${UUID.randomUUID()}.bin")
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
        }
        return instrumentation.targetContext.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)!!
            .also { outputs.add(it) }
    }
    private fun saver(messenger: Messenger, jobs: MutableList<() -> Unit>) {
        ui { activity.saver = AndroidFileSaver(activity, messenger) { jobs.add(it) } }
    }
    private fun save(messenger: Messenger, bytes: ByteArray): Reply {
        var reply: Reply? = null
        ui { reply = messenger.call("org.ffido/files", "saveUue", mapOf("bytes" to bytes, "name" to "test.bin")) }
        return reply!!
    }
    fun testFilePickerCancelAndRecreationCompleteEachResultOnce() {
        val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>(); saver(messenger, jobs)
        val cancelled = save(messenger, byteArrayOf(1, 2))
        ui { activity.saver!!.returned(Activity.RESULT_CANCELED, null); activity.saver!!.returned(Activity.RESULT_CANCELED, null) }
        assertEquals(1, cancelled.count); assertEquals(false, cancelled.value)
        val detached = save(messenger, byteArrayOf(3, 4)); val old = activity.saver!!
        recreate()
        ui { old.detach(); old.returned(Activity.RESULT_CANCELED, null) }
        assertEquals(1, detached.count); assertEquals("detached", detached.error); assertTrue(jobs.isEmpty())
    }
    fun testFailedFileWriteCompletesOnceAndAllowsRetry() {
        val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>(); saver(messenger, jobs)
        val failed = save(messenger, byteArrayOf(1))
        ui { activity.saver!!.returned(Activity.RESULT_OK, Intent().setData(Uri.parse("content://ffido.invalid/missing"))) }
        Thread(jobs.removeAt(0)).apply { start(); join() }; await { failed.count == 1 }
        assertEquals("save", failed.error)
        val retry = save(messenger, byteArrayOf(2))
        ui { activity.saver!!.returned(Activity.RESULT_CANCELED, null) }
        assertEquals(1, retry.count); assertEquals(false, retry.value); assertEquals(1, failed.count)
    }
    fun testLateFileWritePreservesBytesAndCannotCompleteNewWindowResult() {
        val messenger = Messenger(); val jobs = mutableListOf<() -> Unit>(); saver(messenger, jobs)
        val firstBytes = ByteArray(65536) { (it % 251).toByte() }; val firstUri = output()
        val first = save(messenger, firstBytes)
        ui {
            activity.saver!!.returned(Activity.RESULT_OK, Intent().setData(firstUri))
            activity.saver!!.returned(Activity.RESULT_OK, Intent().setData(firstUri))
        }
        assertEquals(1, jobs.size)
        recreate()
        assertEquals(1, first.count); assertEquals("detached", first.error)
        val fresh = Messenger(); saver(fresh, jobs)
        val secondBytes = byteArrayOf(9, 8, 7); val secondUri = output(); val second = save(fresh, secondBytes)
        ui { activity.saver!!.returned(Activity.RESULT_OK, Intent().setData(secondUri)) }
        Thread(jobs.removeAt(0)).apply { start(); join() }; instrumentation.waitForIdleSync()
        assertEquals(0, second.count); assertEquals(1, first.count)
        Thread(jobs.removeAt(0)).apply { start(); join() }; await { second.count == 1 }
        assertEquals(true, second.value)
        val resolver = instrumentation.targetContext.contentResolver
        assertTrue(firstBytes.contentEquals(resolver.openInputStream(firstUri)!!.use { it.readBytes() }))
        assertTrue(secondBytes.contentEquals(resolver.openInputStream(secondUri)!!.use { it.readBytes() }))
    }
}
