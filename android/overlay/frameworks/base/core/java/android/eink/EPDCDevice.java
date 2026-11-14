package android.eink;

/**
 * Compatibility stub for the Kindle E Ink SDK class used by reader apps
 * (com.zhangyue.iReader.Eink and others). AOSP has no EPDC framework; the
 * display itself is driven by veradroid-epd through /dev/epd.
 */
public class EPDCDevice {
    public static final int UPDATE_MODE_PARTIAL = 0;
    public static final int UPDATE_MODE_FULL = 1;
    public static final int UPDATE_MODE_FAST = 2;

    public static class EPDCDeviceInfo {
        public int width = 0;
        public int height = 0;
        public int updateMode = 0;
        public int waveformMode = 0;
        public EPDCDeviceInfo() { }
    }

    private static final EPDCDevice INSTANCE = new EPDCDevice();
    private int updateMode = 0;
    private int waveformMode = 0;

    public EPDCDevice() { }
    public static EPDCDevice getInstance() { return INSTANCE; }
    public static EPDCDevice getEPDCDevice() { return INSTANCE; }
    public EPDCDeviceInfo getEPDCDeviceInfo() { return new EPDCDeviceInfo(); }
    public EPDCDeviceInfo getEpdcDeviceInfo() { return new EPDCDeviceInfo(); }
    public int getWidth() { return 0; }
    public int getHeight() { return 0; }
    public int getUpdateMode() { return updateMode; }
    public void setUpdateMode(int mode) { updateMode = mode; }
    public int getWaveformMode() { return waveformMode; }
    public void setWaveformMode(int mode) { waveformMode = mode; }
    public void enableEPDC() { }
    public void disableEPDC() { }
    public boolean updateScreen() { return true; }
    public boolean updateScreen(int mode) { return true; }
    public boolean updateScreen(int left, int top, int right, int bottom, int mode) { return true; }
    public boolean update(int left, int top, int right, int bottom, int mode) { return true; }
    public boolean update() { return true; }
    public boolean update(int mode) { return true; }
    public void setScreenUpdateMode(int mode) { updateMode = mode; }
    public int getScreenUpdateMode() { return updateMode; }
    public void requestFullUpdate() { }
    public void requestPartialUpdate() { }
}
