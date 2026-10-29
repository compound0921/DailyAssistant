package com.dailyassistant.daily_assistant

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 在通知栏常驻显示最近一条未完成日程，并附带剩余待办数量。
 *
 * 直接读取 FlutterSharedPreferences，不依赖 Flutter 引擎，因此应用被划掉后
 * 仍能每分钟刷新；没有待完成日程时自动结束。
 */
class DeadlinePinService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val postedCards = mutableSetOf<Int>()

    private val tick = object : Runnable {
        override fun run() {
            if (refresh()) handler.postDelayed(this, REFRESH_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val content = currentContent()
        if (content == null) {
            // startForegroundService 后必须 5 秒内调用 startForeground，
            // 否则系统会抛 ForegroundServiceDidNotStartInTimeException 导致闪退。
            startForegroundCompat(buildIdleNotification())
            stopSelfAndCancel()
            return START_NOT_STICKY
        }
        postCards(content)
        startForegroundCompat(buildNotification(content))
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, REFRESH_INTERVAL_MS)
        scheduleWatchdog(this)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        cancelWatchdog(this)
        clearCards()
        removeForeground()
        super.onDestroy()
    }

    private fun refresh(): Boolean {
        val content = currentContent()
        if (content == null) {
            stopSelfAndCancel()
            return false
        }
        postCards(content)
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(content))
        return true
    }

    private fun currentContent(): PinContent? {
        val preferences = getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)
        val raw = preferences.getString(DEADLINES_KEY, null) ?: return null
        val horizonMinutes = preferences.getLong(HORIZON_KEY, DEFAULT_MINUTES)
        val scaleMinutes = preferences.getLong(SCALE_KEY, DEFAULT_MINUTES)
        val items = try {
            JSONArray(raw)
        } catch (_: Exception) {
            return null
        }

        val now = Date()
        val pending = mutableListOf<PendingDeadline>()
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            if (item.optBoolean("completed", false)) continue
            val due = parseDate(item.optString("dueAt", "")) ?: continue
            if (!due.after(now)) continue
            // 显示范围之外的日程不进通知。
            if (horizonMinutes > 0 && due.time - now.time > horizonMinutes * 60_000L) {
                continue
            }
            pending.add(
                PendingDeadline(
                    due = due,
                    title = item.optString("title", "").ifBlank { "日程" },
                ),
            )
        }
        if (pending.isEmpty()) return null

        pending.sortBy { it.due.time }
        val nearest = pending.first()
        val body = buildString {
            append(formatDue(nearest.due))
            append(" 截止 · ")
            append(remainingText(nearest.due, now))
            if (pending.size > 1) {
                append(" · 另有 ")
                append(pending.size - 1)
                append(" 项待办")
            }
        }
        // 最近一条留在汇总里，其余日程各发一张分组卡片。
        val cards = pending.drop(1).take(MAX_CARDS).map { item ->
            PinCard(
                title = shortTitle(item.title),
                body = "${formatDue(item.due)} 截止 · " +
                    remainingText(item.due, now),
                progress = progressOf(item.due, now, scaleMinutes),
            )
        }
        return PinContent(
            title = nearest.title,
            body = body,
            progress = progressOf(nearest.due, now, scaleMinutes),
            cards = cards,
        )
    }

    /** 蓝条长度 = 剩余时间 / 标准时间；越临近截止越短。 */
    private fun progressOf(due: Date, now: Date, scaleMinutes: Long): Int {
        val remainingMinutes = ((due.time - now.time) / 60_000L).coerceAtLeast(0)
        val scale = if (scaleMinutes < 60) 60 else scaleMinutes
        return ((remainingMinutes * 100) / scale).toInt().coerceIn(0, 100)
    }

    private fun buildNotification(content: PinContent): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_deadline)
            .setContentTitle(content.title)
            .setContentText(content.body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent())
            .setProgress(100, content.progress, false)

        // 汇总不参与分组：作为分组汇总会被部分系统隐藏，导致最近一条消失。
        return builder.build()
    }

    /** 没有待完成日程时的占位通知，只为满足前台服务的启动要求，随后立即移除。 */
    private fun buildIdleNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_deadline)
            .setContentTitle("日程")
            .setContentText("没有待完成日程")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun buildCard(card: PinCard): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_deadline)
            .setContentTitle(card.title)
            .setContentText(card.body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent())
            .setProgress(100, card.progress, false)
            .setGroup(GROUP_KEY)
            .build()
    }

    private fun openAppIntent(): PendingIntent {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 每条其它日程各发一条通知，展开后就是多张卡片。 */
    private fun postCards(content: PinContent) {
        val manager = getSystemService(NotificationManager::class.java)
        val ids = mutableSetOf<Int>()
        // 倒序发布：最新的通知排在最上面，让最近截止的一条排第一。
        for ((index, card) in content.cards.withIndex().toList().reversed()) {
            val id = CARD_ID_BASE + index
            ids.add(id)
            manager.notify(id, buildCard(card))
        }
        (postedCards - ids).forEach { manager.cancel(it) }
        postedCards.clear()
        postedCards.addAll(ids)
    }

    private fun clearCards() {
        val manager = getSystemService(NotificationManager::class.java)
        postedCards.forEach { manager.cancel(it) }
        postedCards.clear()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "日程常驻",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "在通知栏常驻显示最近一条待完成日程"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun removeForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun stopSelfAndCancel() {
        handler.removeCallbacks(tick)
        removeForeground()
        stopSelf()
    }

    companion object {
        const val ACTION_TICK = "com.dailyassistant.daily_assistant.action.PIN_TICK"

        private const val PREFERENCES_NAME = "FlutterSharedPreferences"
        private const val DEADLINES_KEY = "flutter.deadlines_v1"
        private const val HORIZON_KEY = "flutter.deadline_pin_horizon_minutes_v1"
        private const val SCALE_KEY = "flutter.deadline_pin_scale_minutes_v1"
        private const val CHANNEL_ID = "deadline_pinned"
        private const val GROUP_KEY = "deadline_pin_group"
        private const val NOTIFICATION_ID = 47001
        private const val CARD_ID_BASE = 47010
        private const val MAX_CARDS = 5
        private const val DEFAULT_MINUTES = 24 * 60L
        private const val REFRESH_INTERVAL_MS = 60_000L
        private const val WATCHDOG_INTERVAL_MS = 5 * 60 * 1000L
        private const val WATCHDOG_REQUEST = 47002

        private fun watchdogIntent(context: Context): PendingIntent {
            val intent = Intent(context, DeadlinePinReceiver::class.java)
                .setAction(ACTION_TICK)
            return PendingIntent.getBroadcast(
                context,
                WATCHDOG_REQUEST,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** 被划掉后进程可能被冻结，只有闹钟能把应用唤醒补发通知。 */
        fun scheduleWatchdog(context: Context) {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            val pending = watchdogIntent(context)
            val triggerAt = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    !manager.canScheduleExactAlarms()
                ) {
                    manager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pending,
                    )
                } else {
                    manager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pending,
                    )
                }
            } catch (_: Exception) {
                try {
                    manager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pending,
                    )
                } catch (_: Exception) {
                    // 闹钟不可用时保持普通定时刷新。
                }
            }
        }

        fun cancelWatchdog(context: Context) {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            val pending = watchdogIntent(context)
            manager.cancel(pending)
            pending.cancel()
        }

        /** 启动或刷新常驻通知；服务会自行判断是否需要继续运行。 */
        fun start(context: Context) {
            val intent = Intent(context, DeadlinePinService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // 后台启动受限时忽略，下次打开应用会重试。
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, DeadlinePinService::class.java))
            } catch (_: Exception) {
                // 服务不存在时无需处理。
            }
            cancelWatchdog(context)
        }
    }
}

private data class PendingDeadline(
    val due: Date,
    val title: String,
)

private data class PinCard(
    val title: String,
    val body: String,
    val progress: Int,
)

private data class PinContent(
    val title: String,
    val body: String,
    val progress: Int,
    val cards: List<PinCard>,
)

/** 通知标题过长会挤掉时间信息，折叠展示。 */
private fun shortTitle(title: String): String =
    if (title.length <= 16) title else title.take(15) + "…"

private val DATE_PATTERNS = listOf(
    "yyyy-MM-dd'T'HH:mm:ss.SSS",
    "yyyy-MM-dd'T'HH:mm:ss",
    "yyyy-MM-dd'T'HH:mm",
)

private fun parseDate(raw: String): Date? {
    if (raw.isEmpty()) return null
    for (pattern in DATE_PATTERNS) {
        try {
            return SimpleDateFormat(pattern, Locale.US).parse(raw)
        } catch (_: Exception) {
            // 尝试下一种格式。
        }
    }
    return null
}

private fun formatDue(due: Date): String {
    val now = Calendar.getInstance()
    val target = Calendar.getInstance().apply { time = due }
    val tomorrow = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
    val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(due)
    return when {
        sameDay(now, target) -> "今天 $time"
        sameDay(tomorrow, target) -> "明天 $time"
        now.get(Calendar.YEAR) == target.get(Calendar.YEAR) ->
            SimpleDateFormat("M 月 d 日 HH:mm", Locale.getDefault()).format(due)
        else -> SimpleDateFormat("yyyy 年 M 月 d 日 HH:mm", Locale.getDefault()).format(due)
    }
}

private fun sameDay(left: Calendar, right: Calendar): Boolean =
    left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
        left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)

private fun remainingText(due: Date, now: Date): String {
    val minutes = ((due.time - now.time) / 60_000L).coerceAtLeast(0)
    return when {
        minutes < 1 -> "不足 1 分钟"
        minutes < 60 -> "剩 $minutes 分钟"
        minutes < 24 * 60 -> {
            val hours = minutes / 60
            val rest = minutes % 60
            if (rest == 0L) "剩 $hours 小时" else "剩 $hours 小时 $rest 分"
        }
        else -> {
            val days = minutes / (24 * 60)
            val hours = (minutes % (24 * 60)) / 60
            if (hours == 0L) "剩 $days 天" else "剩 $days 天 $hours 小时"
        }
    }
}
