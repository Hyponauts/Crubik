package com.example.crubik

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    private var pendingPicker: MethodChannel.Result? = null
    private var selectedDestination: Uri? = null
    private var isWriting = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crubik/solve_export")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "chooseDestination" -> {
                        if (pendingPicker != null || selectedDestination != null || isWriting) {
                            result.error("export_busy", "A file export is already in progress", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(
                                    Intent.EXTRA_TITLE,
                                    call.argument<String>("fileName") ?: "crubik-solves.json",
                                )
                            }
                            selectedDestination = null
                            pendingPicker = result
                            startActivityForResult(intent, EXPORT_REQUEST_CODE)
                        } catch (error: Exception) {
                            pendingPicker = null
                            result.error("export_picker_failed", null, null)
                        }
                    }
                    "writeChosen" -> {
                        val destination = selectedDestination
                        if (destination == null || isWriting) {
                            result.error("export_destination_failed", null, null)
                            return@setMethodCallHandler
                        }
                        try {
                            val sourcePath = call.argument<String>("sourcePath")
                                ?: throw IllegalArgumentException("Missing export file")
                            val source = File(sourcePath).canonicalFile
                            val cachePath = cacheDir.canonicalPath + File.separator
                            require(source.path.startsWith(cachePath) && source.isFile) {
                                "Export file must be in the app cache"
                            }
                            isWriting = true
                            Thread {
                                try {
                                    val output = contentResolver.openOutputStream(destination)
                                        ?: throw IOException("Cannot open export destination")
                                    output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
                                    runOnUiThread {
                                        isWriting = false
                                        selectedDestination = null
                                        result.success(null)
                                    }
                                } catch (error: Exception) {
                                    runOnUiThread {
                                        isWriting = false
                                        result.error("export_destination_failed", null, null)
                                    }
                                }
                            }.start()
                        } catch (error: Exception) {
                            isWriting = false
                            result.error("export_prepare_failed", null, null)
                        }
                    }
                    "clearDestination" -> {
                        val incompleteDocument = selectedDestination
                        if (incompleteDocument == null || isWriting) {
                            result.success(null)
                        } else {
                            selectedDestination = null
                            Thread {
                                // CREATE_DOCUMENT returns a new file, not an existing one.
                                runCatching {
                                    DocumentsContract.deleteDocument(contentResolver, incompleteDocument)
                                }
                            }.start()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android activity result callback for the system document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != EXPORT_REQUEST_CODE) return

        val response = pendingPicker ?: return
        pendingPicker = null
        if (resultCode != Activity.RESULT_OK) {
            response.success(null)
            return
        }

        selectedDestination = data?.data
        if (selectedDestination == null) {
            response.error("export_picker_failed", null, null)
            return
        }
        // Dart's system temp directory can be the sibling code_cache directory.
        response.success(cacheDir.path)
    }

    companion object {
        private const val EXPORT_REQUEST_CODE = 0x4352
    }
}
