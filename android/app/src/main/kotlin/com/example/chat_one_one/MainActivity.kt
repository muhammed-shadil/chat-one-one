package com.example.chat_one_one

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots and screen recording everywhere in the app (they
        // come out black), before anything is drawn. This also blanks the app
        // in the recent-apps switcher and on screen casting.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)

        // High importance, so new messages pop up on screen. Push notifications
        // use this channel (see default_notification_channel_id in the manifest).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "messages", "Messages", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "New messages in the chat" }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
