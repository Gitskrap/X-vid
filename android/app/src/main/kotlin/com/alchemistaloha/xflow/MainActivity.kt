package com.alchemistaloha.xflow

import android.os.SystemClock
import android.view.KeyEvent
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Volume buttons control Cast while connected; otherwise Android behaves normally. */
class MainActivity : FlutterFragmentActivity() {
    private var previousSession: CastSession? = null
    private var requestedVolume = Double.NaN
    private var lastChangeAt = 0L

    private fun currentCast(): CastSession? = try {
        CastContext.getSharedInstance(this).sessionManager.currentCastSession
            ?.takeIf { it.isConnected }
    } catch (_: Exception) {
        null
    }

    private fun changeCastVolume(session: CastSession, direction: Int) {
        val now = SystemClock.elapsedRealtime()
        if (previousSession !== session || requestedVolume.isNaN() || now - lastChangeAt > 1500) {
            requestedVolume = session.volume
        }
        previousSession = session
        requestedVolume = (requestedVolume + direction * 0.05).coerceIn(0.0, 1.0)
        if (direction > 0 && session.isMute) session.setMute(false)
        session.setVolume(requestedVolume)
        lastChangeAt = now
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val direction = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 1
            KeyEvent.KEYCODE_VOLUME_DOWN -> -1
            else -> return super.dispatchKeyEvent(event)
        }
        val session = currentCast() ?: return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN) {
            try {
                changeCastVolume(session, direction)
            } catch (_: Exception) {
                return super.dispatchKeyEvent(event)
            }
        }
        // Consume both key-down and key-up only during a Cast session.
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fr.twittervideo.client/cast_volume").setMethodCallHandler { call, result ->
            val session = currentCast()
            when (call.method) {
                "getVolume" -> {
                    try { result.success(session?.volume) }
                    catch (_: Exception) { result.success(null) }
                }
                "setVolume" -> {
                    val requested = call.argument<Double>("volume")
                    if (session == null || requested == null || !requested.isFinite()) {
                        result.error("NOT_CONNECTED", "Aucun Chromecast connecté", null)
                    } else {
                        try {
                            val value = requested.coerceIn(0.0, 1.0)
                            session.setVolume(value)
                            if (value > 0.0 && session.isMute) session.setMute(false)
                            previousSession = session
                            requestedVolume = value
                            lastChangeAt = SystemClock.elapsedRealtime()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("VOLUME_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
