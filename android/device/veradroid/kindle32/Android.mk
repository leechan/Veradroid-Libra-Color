# packages/apps/ has its own Android.mk at the top (VeraHome + VeraIME, see android/packages/apps-Android.mk). The AOSP build stops
# looking for Android.mk files below a directory that has one, so every stock app under packages/apps
# (PackageInstaller, KeyChain, CertInstaller, ...) silently drops out of a clean build. PackageManagerService
# cannot boot without an installer ("There must be exactly one installer; found []"). Pull it back in here.
# Only built when a product lists it (veradroid_kindle32.mk does).
include packages/apps/PackageInstaller/Android.mk
