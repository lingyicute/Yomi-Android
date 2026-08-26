package chat.lyi.yomi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the background sync service after reboot or an app update.
 * Chinese OEM firmwares often also emit QUICKBOOT_POWERON instead of
 * the standard BOOT_COMPLETED action.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "Boot/update event: $action")
        if (!BackgroundSyncService.isEnabled(context)) {
            Log.i(TAG, "Background sync disabled, not starting after $action")
            return
        }
        BackgroundSyncService.start(context)
    }

    companion object {
        private const val TAG = "YomiBgSync"
    }
}
