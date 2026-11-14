EPDCDevice.java: compatibility stub for the Kindle / Onyx-style android.eink.EPDCDevice class that some Chinese reader
apps call through reflection or direct linking (com.zhangyue.iReader.Eink and others); without it they die with
NoClassDefFoundError. It is compiled into framework.jar (core/java/** is all-java-files-under). It used to exist only in
the build host's source tree; apply-patches.sh now copies it from here like every other overlay file.
