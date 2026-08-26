package chat.lyi.yomi

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * Inexact watchdog. If the OEM killed the process, this brings the
 * foreground service (and therefore the Dart sync loop) back.
 */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!BackgroundSyncService.isEnabled(context)) {
            Log.i(TAG, "Watchdog fired but background sync is disabled")
            return
        }
        Log.i(TAG, "Watchdog restarting background sync service")
        BackgroundSyncService.start(context)
        schedule(context)
    }

    companion object {
        private const val TAG = "YomiBgSync"
        private const val REQUEST_CODE = 0x594F4D4A
        private const val INTERVAL_MS = 2 * 60 * 1000L

        fun schedule(context: Context, delayMs: Long = INTERVAL_MS) {
            val app = context.applicationContext
            val alarmManager = app.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val pending = pendingIntent(app)
            val triggerAt = SystemClock.elapsedRealtime() + delayMs
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pending,
                    )
                } else {
                    alarmManager.set(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pending,
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "Unable to schedule watchdog", e)
            }
        }

        fun cancel(context: Context) {
            val app = context.applicationContext
            val alarmManager = app.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            try {
                alarmManager.cancel(pendingIntent(app))
            } catch (e: Exception) {
                Log.w(TAG, "Unable to cancel watchdog", e)
            }
        }

        private fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, WatchdogReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        }
    }
}
