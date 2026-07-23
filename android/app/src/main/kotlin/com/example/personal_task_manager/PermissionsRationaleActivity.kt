package com.example.personal_task_manager

import android.app.Activity
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.TextView

class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 48, 48, 48)
        }
        container.addView(
            TextView(this).apply {
                textSize = 22f
                text = "TaskMaster Pro health data access"
            }
        )
        container.addView(
            TextView(this).apply {
                textSize = 16f
                text = "TaskMaster Pro reads only the health categories you approve, such as steps, exercise, distance, sleep, heart rate, or calories. This information is used for task context and productivity summaries. You can revoke access or delete imported data from Health Connect settings at any time."
            }
        )
        setContentView(container)
    }
}
