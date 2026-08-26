package chat.lyi.yomi

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart ↔ native bridge for the self-hosted background sync service.
 *
 * Channel: `chat.lyi.yomi/background_sync`
 */
object BackgroundSyncBridge : MethodChannel.MethodCallHandler {
    const val CHANNEL = "chat.lyi.yomi/background_sync"
    private const val TAG = "YomiBgSync"

    @Volatile
    private var appContext: Context? = null

    fun register(engine: FlutterEngine, context: Context) {
        appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("no_context", "BackgroundSyncBridge is not attached", null)
            return
        }
        when (call.method) {
            "start" -> {
                BackgroundSyncService.start(context)
                result.success(null)
            }
            "stop" -> {
                BackgroundSyncService.stop(context)
                result.success(null)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations(context))
            }
            "requestIgnoreBatteryOptimizations" -> {
                result.success(requestIgnoreBatteryOptimizations(context))
            }
            "openAutostartSettings" -> {
                result.success(openAutostartSettings(context))
            }
            else -> result.notImplemented()
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isIgnoringBatteryOptimizations(context.packageName) == true
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations(context)) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS failed, opening settings", e)
            openAppDetails(context)
        }
    }

    private fun openAutostartSettings(context: Context): Boolean {
        val candidates = listOf(
            // Xiaomi / HyperOS / MIUI
            component("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            component("com.miui.securitycenter", "com.miui.powercenter.PowerSettings"),
            // Huawei / HarmonyOS
            component("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            component("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            component("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"),
            // Honor
            component("com.hihonor.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            // OPPO / ColorOS / Realme
            component("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            component("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            component("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
            component("com.oplus.safecenter", "com.oplus.safecenter.startupapp.view.StartupAppListActivity"),
            // Vivo / OriginOS / Funtouch
            component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
            component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            component("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            // OnePlus / OxygenOS
            component("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
            // Samsung
            component("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
            component("com.samsung.android.sm_cn", "com.samsung.android.sm.ui.battery.BatteryActivity"),
            // Meizu
            component("com.meizu.safe", "com.meizu.safe.security.SHOW_APPSEC"),
            // Letv
            component("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"),
        )

        for (component in candidates) {
            val intent = Intent().apply {
                component = component
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(context.packageManager) != null) {
                try {
                    context.startActivity(intent)
                    return true
                } catch (e: Exception) {
                    Log.w(TAG, "Autostart activity $component failed", e)
                }
            }
        }
        return openAppDetails(context)
    }

    private fun openAppDetails(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Unable to open application details", e)
            false
        }
    }

    private fun component(pkg: String, cls: String) = ComponentName(pkg, cls)
}
