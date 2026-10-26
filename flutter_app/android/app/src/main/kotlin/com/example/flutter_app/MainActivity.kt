package com.example.flutter_app

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity: FlutterActivity() {
    private val MULTICAST_CHANNEL = "com.offlinemesh/wifi_multicast"
    private var multicastLock: WifiManager.MulticastLock? = null

    private val FILE_VIEWER_CHANNEL = "com.offlinemesh/file_viewer"

    private fun getFileUri(file: File): Uri {
        val cache = cacheDir
        val files = filesDir
        val extCache = externalCacheDir
        val extFiles = getExternalFilesDir(null)

        val isSafe = file.absolutePath.startsWith(cache.absolutePath) ||
                file.absolutePath.startsWith(files.absolutePath) ||
                (extCache != null && file.absolutePath.startsWith(extCache.absolutePath)) ||
                (extFiles != null && file.absolutePath.startsWith(extFiles.absolutePath))

        val fileToServe = if (isSafe) {
            file
        } else {
            val shareDir = File(cache, "shared_files").apply { if (!exists()) mkdirs() }
            val copied = File(shareDir, file.name)
            file.copyTo(copied, overwrite = true)
            copied
        }

        return FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            fileToServe
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val multicastMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MULTICAST_CHANNEL)
        multicastMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        if (multicastLock == null) {
                            multicastLock = wifiManager.createMulticastLock("OfflineMeshMulticastLock").apply {
                                setReferenceCounted(true)
                            }
                        }
                        if (multicastLock?.isHeld != true) {
                            multicastLock?.acquire()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", "Failed to acquire MulticastLock: ${e.message}", null)
                    }
                }
                "releaseMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld == true) {
                            multicastLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", "Failed to release MulticastLock: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        val fileViewerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_VIEWER_CHANNEL)
        fileViewerChannel.setMethodCallHandler { call, result ->
            val filePath = call.argument<String>("filePath")
            val mimeType = call.argument<String>("mimeType") ?: "*/*"

            if (filePath == null) {
                result.error("INVALID_ARGS", "filePath is required", null)
                return@setMethodCallHandler
            }

            val file = File(filePath)
            if (!file.exists()) {
                result.error("NOT_FOUND", "File does not exist: $filePath", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "openFile" -> {
                    try {
                        val uri = getFileUri(file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            clipData = ClipData.newRawUri("", uri)
                        }

                        val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                        for (resolveInfo in resInfoList) {
                            val packageName = resolveInfo.activityInfo.packageName
                            grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(intent, "Open with...")
                        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", "Failed to open file: ${e.message}", null)
                    }
                }
                "shareFile" -> {
                    try {
                        val uri = getFileUri(file)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = ClipData.newRawUri("", uri)
                        }

                        val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                        for (resolveInfo in resInfoList) {
                            val packageName = resolveInfo.activityInfo.packageName
                            grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(intent, "Share via...")
                        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", "Failed to share file: ${e.message}", null)
                    }
                }
                "saveToDownloads" -> {
                    try {
                        val name = call.argument<String>("fileName") ?: file.name
                        val resolver = contentResolver
                        val contentValues = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/OfflineMesh")
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                        }

                        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                        } else {
                            MediaStore.Files.getContentUri("external")
                        }

                        val itemUri = resolver.insert(collection, contentValues)
                        if (itemUri == null) {
                            result.error("SAVE_ERROR", "Could not create destination URI in Downloads", null)
                            return@setMethodCallHandler
                        }

                        resolver.openOutputStream(itemUri)?.use { out ->
                            FileInputStream(file).use { input ->
                                input.copyTo(out)
                            }
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            contentValues.clear()
                            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            resolver.update(itemUri, contentValues, null, null)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", "Failed to save file to Downloads: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
