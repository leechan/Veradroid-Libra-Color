// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * 书库现在是主页里的一个标签（见 {@link LibraryPage}），不再是单独的页面。
 * 这个类只为旧的入口留着：谁启动它，就转到主页的“书库”标签。
 */
public class BookshelfActivity extends Activity {
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        Intent i = new Intent(this, HomeActivity.class);
        i.putExtra("library", true);
        i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NO_ANIMATION);
        startActivity(i);
        overridePendingTransition(0, 0);
        finish();
    }
}
