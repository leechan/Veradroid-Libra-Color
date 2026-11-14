// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

/** Gives the pull-down panel access to the notifications apps post. Enabled by the system setup (init.kindle.rc). */
public class NotifService extends NotificationListenerService {
    static volatile NotifService instance;

    @Override public void onListenerConnected() { instance = this; }
    @Override public void onListenerDisconnected() { if (instance == this) instance = null; }

    static StatusBarNotification[] active() {
        NotifService s = instance;
        if (s == null) return new StatusBarNotification[0];
        try {
            StatusBarNotification[] a = s.getActiveNotifications();
            return a == null ? new StatusBarNotification[0] : a;
        } catch (Throwable t) {
            return new StatusBarNotification[0];
        }
    }
}
