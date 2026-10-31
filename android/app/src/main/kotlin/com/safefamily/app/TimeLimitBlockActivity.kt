package com.safefamily.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Màn chặn khi hết giờ dùng máy / dùng app. Chỉ có chữ và nút về màn hình
 * chính; con bấm "Xin thêm giờ" thì phụ huynh xác thực trong SafeFamily và chọn số phút.
 */
class TimeLimitBlockActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val message = intent.getStringExtra(EXTRA_MESSAGE) ?: "Hết giờ dùng hôm nay"
        val density = resources.displayMetrics.density
        val pad = (24 * density).toInt()

        val title = TextView(this).apply {
            text = message
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val hint = TextView(this).apply {
            text = if (intent.getBooleanExtra(EXTRA_NEEDS_REVIEW, false)) {
                "Con cần bố mẹ cho phép trước khi dùng app này."
            } else {
                "Nhờ bố mẹ nếu con cần thêm giờ nhé!"
            }
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, pad / 2, 0, pad)
        }
        // Chỉ hiện khi lý do là hết hạn mức; giờ ngủ không xin thêm được ở đây.
        val canRequest = intent.getBooleanExtra(EXTRA_CAN_REQUEST, false)
        val request = Button(this).apply {
            text = "Xin thêm giờ"
            setOnClickListener { requestMoreTime() }
        }
        // App mới cài: con đưa máy cho phụ huynh duyệt ngay trong SafeFamily.
        val review = Button(this).apply {
            text = "Nhờ bố mẹ duyệt"
            setOnClickListener {
                NewApps.openReview(this@TimeLimitBlockActivity)
                finish()
            }
        }
        // SOS: gọi/nhắn người nhà bằng app Điện thoại/Tin nhắn của máy (không cần quyền CALL_PHONE, SEND_SMS).
        val contacts = GuardPrefs.contacts(this)
        val emergency = contacts.firstOrNull { it.emergency } ?: contacts.firstOrNull()
        val sos = Button(this).apply {
            text = if (emergency != null) "SOS: gọi ${emergency.label}" else "SOS: mở bàn phím gọi"
            setOnClickListener { dial(emergency?.phone) }
        }
        val sms = Button(this).apply {
            text = "Nhắn \"Con cần giúp\""
            setOnClickListener { sendHelpSms(emergency!!.phone) }
        }
        val family = Button(this).apply {
            text = "Liên hệ người nhà"
            setOnClickListener { pickContact(contacts) }
        }
        val home = Button(this).apply {
            text = "Về màn hình chính"
            setOnClickListener { goHome() }
        }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(pad, pad, pad, pad)
                setBackgroundColor(BACKGROUND)
                addView(title)
                addView(hint)
                if (canRequest) addView(request)
                if (intent.getBooleanExtra(EXTRA_NEEDS_REVIEW, false)) addView(review)
                addView(sos)
                if (emergency != null) addView(sms)
                if (contacts.size > 1) addView(family)
                addView(home)
            },
        )
    }

    @Deprecated("Back cũng về màn hình chính, không quay lại app bị chặn")
    override fun onBackPressed() = goHome()

    /**
     * Máy đã ghép đôi: con chọn số phút xin rồi gửi cho mẹ ở xa (API-06), hoặc đưa máy cho phụ huynh
     * duyệt tại chỗ như cũ. Máy chưa ghép: chỉ cách tại chỗ.
     */
    private fun requestMoreTime() {
        if (!FamilySync.isConfigured(this)) return requestOnThisDevice()
        val choices = intArrayOf(5, 15, 30)
        AlertDialog.Builder(this)
            .setTitle("Xin bố mẹ thêm giờ")
            .setItems(choices.map { "Xin $it phút" }.toTypedArray()) { _, i ->
                FamilySync.queueRequest(this, FamilySync.REQUEST_EXTRA_TIME, choices[i])
                android.widget.Toast.makeText(this, "Đã gửi cho bố mẹ. Chờ bố mẹ trả lời nhé.", android.widget.Toast.LENGTH_LONG).show()
            }
            .setNeutralButton("Đưa máy cho bố mẹ") { _, _ -> requestOnThisDevice() }
            .setNegativeButton("Thôi", null)
            .show()
    }

    /** Phụ huynh xác thực trong SafeFamily rồi chọn 5/15/30 phút. */
    private fun requestOnThisDevice() {
        GuardPrefs.setExtraTimePending(this, true)
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }

    private fun dial(phone: String?) {
        val uri = if (phone.isNullOrEmpty()) Uri.parse("tel:") else Uri.fromParts("tel", phone, null)
        runCatching { startActivity(Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    private fun sendHelpSms(phone: String) {
        runCatching {
            startActivity(
                Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", phone, null))
                    .putExtra("sms_body", "Con cần giúp")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun pickContact(contacts: List<GuardPrefs.Contact>) {
        AlertDialog.Builder(this)
            .setTitle("Gọi người nhà")
            .setItems(contacts.map { "${it.label}  ${it.phone}" }.toTypedArray()) { _, i ->
                dial(contacts[i].phone)
            }
            .show()
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        finish()
    }

    companion object {
        const val EXTRA_MESSAGE = "message"
        const val EXTRA_CAN_REQUEST = "can_request"
        const val EXTRA_NEEDS_REVIEW = "needs_review"
        private const val BACKGROUND = 0xFF00796B.toInt()
    }
}
