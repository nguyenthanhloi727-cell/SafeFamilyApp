package com.safefamily.safe_family_app_nguyenthanhloi

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth yêu cầu FlutterFragmentActivity (hộp thoại BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cho Dart biết máy có phần cứng vân tay / khuôn mặt hay không
        // (local_auth chỉ báo loại yếu/mạnh, không báo vân tay hay khuôn mặt).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safefamily/biometric_hardware")
            .setMethodCallHandler { call, result ->
                if (call.method == "features") {
                    val pm = packageManager
                    val atLeastQ = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    result.success(
                        mapOf(
                            "fingerprint" to pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT),
                            "face" to (atLeastQ && pm.hasSystemFeature(PackageManager.FEATURE_FACE)),
                            "iris" to (atLeastQ && pm.hasSystemFeature(PackageManager.FEATURE_IRIS)),
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
