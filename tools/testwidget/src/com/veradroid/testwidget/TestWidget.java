package com.veradroid.testwidget;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.widget.RemoteViews;

/** 最小的小部件：显示“测试小部件”和最后一次更新的时间。 */
public class TestWidget extends AppWidgetProvider {
    @Override public void onUpdate(Context c, AppWidgetManager m, int[] ids) {
        String t = new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(new java.util.Date());
        for (int id : ids) {
            RemoteViews rv = new RemoteViews(c.getPackageName(), R.layout.test_widget);
            rv.setTextViewText(R.id.time, "AppWidgetHost OK · 更新于 " + t + " · id " + id);
            m.updateAppWidget(id, rv);
        }
    }
}
