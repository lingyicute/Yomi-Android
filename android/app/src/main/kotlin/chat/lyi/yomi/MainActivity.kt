package chat.lyi.yomi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.FlutterInjector

import android.content.Context
import androidx.multidex.MultiDex

class MainActivity : FlutterActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        MultiDex.install(this)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Engine (and the background-sync MethodChannel) is configured in
        // provideEngine so the same instance can be reused by the FGS.
        BackgroundSyncBridge.register(flutterEngine, applicationContext)
    }

    companion object {
        var engine: FlutterEngine? = null

        fun provideEngine(context: Context): FlutterEngine {
            val app = context.applicationContext
            val existing = engine
            if (existing != null) {
                BackgroundSyncBridge.register(existing, app)
                return existing
            }
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(app)
                loader.ensureInitializationComplete(app, null)
            }
            val eng = FlutterEngine(app, emptyArray(), true, false)
            BackgroundSyncBridge.register(eng, app)
            engine = eng
            return eng
        }
    }
}
