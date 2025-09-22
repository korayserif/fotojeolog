package com.example.yeni_clean

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"app/signing"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"getSigning" -> {
					try {
						val pm = applicationContext.packageManager
						val pkg = applicationContext.packageName
						val sigBytes: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
							val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
								pm.getPackageInfo(
									pkg,
									PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
								)
							} else {
								@Suppress("DEPRECATION")
								pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
							}
							val signingInfo = info.signingInfo
							val signers = signingInfo?.apkContentsSigners
							if (signers != null && signers.isNotEmpty()) signers[0].toByteArray() else null
						} else {
							@Suppress("DEPRECATION")
							val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES)
							@Suppress("DEPRECATION")
							val sigs = info.signatures
							if (sigs != null && sigs.isNotEmpty()) sigs[0].toByteArray() else null
						}

						if (sigBytes == null) {
							result.error("NO_SIGNATURE", "İmza bilgisi alınamadı", null)
							return@setMethodCallHandler
						}

						fun digest(alg: String): String {
							val md = MessageDigest.getInstance(alg)
							val d = md.digest(sigBytes)
							return d.joinToString(":") { b -> "%02X".format(b) }
						}

						val sha1 = digest("SHA-1")
						val sha256 = digest("SHA-256")
						val map = mapOf(
							"packageName" to pkg,
							"sha1" to sha1,
							"sha256" to sha256
						)
						result.success(map)
					} catch (e: Exception) {
						result.error("ERR", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}
}
