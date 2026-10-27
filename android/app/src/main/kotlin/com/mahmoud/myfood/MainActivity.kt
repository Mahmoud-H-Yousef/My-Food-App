package com.mahmoud.myfood

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Fragment activity: Health Connect asks for permissions with registerForActivityResult.
class MainActivity : FlutterFragmentActivity() {
    private var pendingCamera: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The photo picker's camera needs the CAMERA permission granted first, because the app declares it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myfood/permissions").setMethodCallHandler { call, result ->
            if (call.method != "camera") {
                result.notImplemented()
            } else if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
            } else {
                pendingCamera = result
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQUEST) {
            pendingCamera?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingCamera = null
        }
    }

    companion object {
        private const val CAMERA_REQUEST = 4711
    }
}
