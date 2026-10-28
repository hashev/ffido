package io.github.hashev.ffido

import androidx.core.content.FileProvider

/** Only the private image-share directory is exposed, with read-only grants. */
class ImageFileProvider : FileProvider() {
    override fun openFile(uri: android.net.Uri, mode: String): android.os.ParcelFileDescriptor {
        require(mode == "r") { "Read-only image" }
        return super.openFile(uri, mode) ?: throw java.io.FileNotFoundException()
    }
    override fun delete(uri: android.net.Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: android.net.Uri, values: android.content.ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
