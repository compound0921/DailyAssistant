package com.dailyassistant.daily_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 常驻通知的看门狗：闹钟每次唤醒就重新拉起服务，服务发现通知不在会立即补发。
 * Android 14 起用户可划掉前台服务通知，且被划掉后进程可能被冻结，只能靠闹钟唤醒。
 */
class DeadlinePinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != DeadlinePinService.ACTION_TICK) return
        DeadlinePinService.start(context)
    }
}
