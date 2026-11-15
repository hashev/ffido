package io.github.hashev.ffido

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import java.lang.ref.WeakReference

// Debug-only host: real Activity recreation, controlled system-dialog boundary.
class LifecycleTestActivity : Activity() {
    companion object { var current: WeakReference<LifecycleTestActivity>? = null }
    var updater: AndroidUpdater? = null
    var saver: AndroidFileSaver? = null
    var requests = 0
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        current = WeakReference(this)
    }
    @Deprecated("Test host records the dialog boundary")
    override fun startActivityForResult(intent: Intent, requestCode: Int) { requests++ }
    override fun onDestroy() {
        updater?.detach(); saver?.detach()
        super.onDestroy()
    }
}
