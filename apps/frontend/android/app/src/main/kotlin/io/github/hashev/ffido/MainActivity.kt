package io.github.hashev.ffido

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var imageActions: AndroidImageActions? = null
    private var updater: AndroidUpdater? = null
    private var fileSaver: AndroidFileSaver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imageActions = AndroidImageActions(this, flutterEngine.dartExecutor.binaryMessenger)
        updater = AndroidUpdater(this, flutterEngine.dartExecutor.binaryMessenger)
        fileSaver = AndroidFileSaver(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        imageActions?.detach()
        updater?.detach()
        fileSaver?.detach()
        super.onDestroy()
    }

    @Deprecated("Android callback retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == AndroidImageActions.requestCode) { imageActions?.returned(resultCode); return }
        if (requestCode == AndroidUpdater.permissionRequest) { updater?.permissionReturned(); return }
        if (requestCode == AndroidFileSaver.requestCode) { fileSaver?.returned(resultCode, data); return }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
