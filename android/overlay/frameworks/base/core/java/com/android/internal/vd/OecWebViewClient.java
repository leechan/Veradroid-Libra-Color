/*
 * VeraDroid: the app's own WebViewClient, wrapped so the per-app WebView CSS (OecConfig, OEC_W*) is injected when a page
 * becomes visible and when it has finished loading. Every callback is passed on to the app's client unchanged.
 * Only used when the app has a WebView rule (WebView.setWebViewClient); a null client is never wrapped (a WebView without
 * a client opens links in another app, a non-null one would change that).
 */
package com.android.internal.vd;

import android.graphics.Bitmap;
import android.net.http.SslError;
import android.os.Message;
import android.view.InputEvent;
import android.view.KeyEvent;
import android.webkit.ClientCertRequest;
import android.webkit.HttpAuthHandler;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** @hide */
public final class OecWebViewClient extends WebViewClient {
    private final WebViewClient mApp;

    private OecWebViewClient(WebViewClient app) { mApp = app; }

    /** WebView.setWebViewClient: what to hand to the provider. */
    public static WebViewClient wrap(WebViewClient c) {
        if (c == null || c instanceof OecWebViewClient || !OecConfig.webActive()) return c;
        return new OecWebViewClient(c);
    }

    @Override public boolean shouldOverrideUrlLoading(WebView view, String url) { return mApp.shouldOverrideUrlLoading(view, url); }
    @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) { return mApp.shouldOverrideUrlLoading(view, request); }
    @Override public void onPageStarted(WebView view, String url, Bitmap favicon) { mApp.onPageStarted(view, url, favicon); }
    @Override public void onPageFinished(WebView view, String url) { mApp.onPageFinished(view, url); OecConfig.injectWeb(view); }
    @Override public void onLoadResource(WebView view, String url) { mApp.onLoadResource(view, url); }
    @Override public void onPageCommitVisible(WebView view, String url) { OecConfig.injectWeb(view); mApp.onPageCommitVisible(view, url); }
    @Override public WebResourceResponse shouldInterceptRequest(WebView view, String url) { return mApp.shouldInterceptRequest(view, url); }
    @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) { return mApp.shouldInterceptRequest(view, request); }
    @Override @SuppressWarnings("deprecation")
    public void onTooManyRedirects(WebView view, Message cancelMsg, Message continueMsg) { mApp.onTooManyRedirects(view, cancelMsg, continueMsg); }
    @Override public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) { mApp.onReceivedError(view, errorCode, description, failingUrl); }
    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) { mApp.onReceivedError(view, request, error); }
    @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) { mApp.onReceivedHttpError(view, request, errorResponse); }
    @Override public void onFormResubmission(WebView view, Message dontResend, Message resend) { mApp.onFormResubmission(view, dontResend, resend); }
    @Override public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) { mApp.doUpdateVisitedHistory(view, url, isReload); }
    @Override public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) { mApp.onReceivedSslError(view, handler, error); }
    @Override public void onReceivedClientCertRequest(WebView view, ClientCertRequest request) { mApp.onReceivedClientCertRequest(view, request); }
    @Override public void onReceivedHttpAuthRequest(WebView view, HttpAuthHandler handler, String host, String realm) { mApp.onReceivedHttpAuthRequest(view, handler, host, realm); }
    @Override public boolean shouldOverrideKeyEvent(WebView view, KeyEvent event) { return mApp.shouldOverrideKeyEvent(view, event); }
    @Override public void onUnhandledKeyEvent(WebView view, KeyEvent event) { mApp.onUnhandledKeyEvent(view, event); }
    @Override public void onUnhandledInputEvent(WebView view, InputEvent event) { mApp.onUnhandledInputEvent(view, event); }
    @Override public void onScaleChanged(WebView view, float oldScale, float newScale) { mApp.onScaleChanged(view, oldScale, newScale); }
    @Override public void onReceivedLoginRequest(WebView view, String realm, String account, String args) { mApp.onReceivedLoginRequest(view, realm, account, args); }
}
