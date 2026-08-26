package chat.lyi.yomi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Sticky foreground service that keeps the Flutter / Dart isolate alive so the
 * Matrix client can long-poll `/sync` without Firebase or ntfy.
 *
 * The Dart side owns the actual sync loop. This service only:
 *  - holds a dataSync foreground notification (required on modern Android)
 *  - restarts after process death (START_STICKY)
 *  - boots the Flutter engine when started from a BroadcastReceiver
 */
class BackgroundSyncService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startInForeground()
        WatchdogReceiver.schedule(this)
        ensureFlutterEngine()
        Log.i(TAG, "Background sync service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.i(TAG, "Stop requested")
            WatchdogReceiver.cancel(this)
            stopInForeground()
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        startInForeground()
        WatchdogReceiver.schedule(this)
        ensureFlutterEngine()
        return START_STICKY
    }

    override fun onTimeout(startId: Int) {
        // Android 14 dataSync time limit — restart so sync keeps running.
        Log.w(TAG, "onTimeout(startId=$startId), restarting")
        restartSelf()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "onTimeout(startId=$startId, type=$fgsType), restarting")
        restartSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep running after the user swipes the task away.
        Log.i(TAG, "Task removed, service stays alive")
        start(applicationContext)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        WatchdogReceiver.cancel(this)
        Log.i(TAG, "Service destroyed")
        super.onDestroy()
    }

    private fun restartSelf() {
        WatchdogReceiver.schedule(this, delayMs = 1_000L)
        stopInForeground()
        stopSelf()
        start(applicationContext)
    }

    private fun stopInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun ensureFlutterEngine() {
        try {
            val engine = MainActivity.provideEngine(applicationContext)
            if (!engine.dartExecutor.isExecutingDart) {
                engine.localizationPlugin.sendLocalesToFlutter(resources.configuration)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault(),
                )
                Log.i(TAG, "Flutter engine started from background service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Unable to start Flutter engine", e)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台消息同步",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Yomi 在后台接收新消息"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun startInForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val contentIntent = PendingIntent.getActivity(this, 0, launchIntent, flags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Yomi 正在运行")
            .setContentText("后台接收新消息")
            .setSmallIcon(R.drawable.notifications_icon)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        private const val TAG = "YomiBgSync"
        const val CHANNEL_ID = "yomi_background_sync"
        const val NOTIFICATION_ID = 0x594F4D49
        const val ACTION_START = "chat.lyi.yomi.START_BACKGROUND_SYNC"
        const val ACTION_STOP = "chat.lyi.yomi.STOP_BACKGROUND_SYNC"
        private const val PREFS = "yomi_bg_sync"
        private const val ENABLED_KEY = "enabled"

        fun isEnabled(context: Context): Boolean {
            return context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(ENABLED_KEY, false)
        }

        fun setEnabled(context: Context, enabled: Boolean) {
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, enabled)
                .apply()
        }

        fun start(context: Context) {
            val app = context.applicationContext
            setEnabled(app, true)
            val intent = Intent(app, BackgroundSyncService::class.java).setAction(ACTION_START)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    app.startForegroundService(intent)
                } else {
                    app.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unable to start background sync service", e)
            }
        }

        fun stop(context: Context) {
            val app = context.applicationContext
            setEnabled(app, false)
            val intent = Intent(app, BackgroundSyncService::class.java).setAction(ACTION_STOP)
            try {
                app.startService(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Unable to deliver stop intent, stopping directly", e)
                app.stopService(Intent(app, BackgroundSyncService::class.java))
            }
        }
    }
}
