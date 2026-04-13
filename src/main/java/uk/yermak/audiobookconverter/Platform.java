package uk.yermak.audiobookconverter;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.lang.invoke.MethodHandles;
import java.util.List;
import java.util.Properties;

public enum Platform {
    DEV {
    },

    MAC {
        @Override
        protected File getConfigFilePath() {
            // Packaged app: use Apple API via reflection to locate the .app bundle path,
            // then look for path.properties inside Contents/app/ (matches jpackage layout).
            try {
                Class<?> fm = Class.forName("com.apple.eio.FileManager");
                java.lang.reflect.Method m = fm.getMethod("getPathToApplicationBundle");
                String bundlePath = (String) m.invoke(null);
                if (bundlePath != null && !bundlePath.isEmpty()) {
                    File f = new File(bundlePath, "Contents/app/path.properties");
                    if (f.exists()) return f;
                }
            } catch (Exception ignored) {}

            // User override: allows Intel-Mac users (or anyone) to place a custom
            // path.properties in ~/.abc/<version>/ without modifying the project.
            File userOverride = new File(System.getProperty("APP_HOME", ""), "path.properties");
            if (userOverride.exists()) return userOverride;

            // Development fallback: running directly from the project root via Maven/IDE.
            File devConfig = new File("external/x64/mac/path.properties");
            if (devConfig.exists()) return devConfig;

            // Assembled-structure fallback (matches mac-installer.xml assembly output).
            return new File("app/path.properties");
        }
    },

    LINUX {
        @Override
        protected File getConfigFilePath() {
            return new File("../lib/app/path.properties");

        }
    },

    WINDOWS {
        @Override
        public Process createProcess(List<String> arguments) throws IOException {
            return Runtime.getRuntime().exec( String.join(" ", arguments));

        }
    };
    static Platform current;
    private static Properties properties = new Properties();

    static {
        if (LINUX.isLinux()) current = LINUX;
        if (MAC.isMac()) current = MAC;
        if (WINDOWS.isWindows()) current = WINDOWS;
        if (DEV.isDebug()) current = DEV;
        properties = current.loadAppProperties();
    }

    final static Logger logger = LoggerFactory.getLogger(MethodHandles.lookup().lookupClass());


    public static final String FFPROBE = current.getPath("ffprobe");
    public static final String MP4INFO = current.getPath("mp4info").replaceAll(" ", "\\ ");
    public static final String MP4ART = current.getPath("mp4art").replaceAll(" ", "\\ ");
    public final static String FFMPEG = current.getPath("ffmpeg").replaceAll(" ", "\\ ");


    private boolean isDebug() {
        String debug = System.getenv("DEBUG");
        return (StringUtils.isNotEmpty(debug)) && Boolean.parseBoolean(debug);
    }

    public boolean isWindows() {
        return System.getProperty("os.name").contains("Windows");
    }

    public boolean isLinux() {
        return System.getProperty("os.name").contains("Linux");
    }

    public boolean isMac() {
        return System.getProperty("os.name").contains("Mac OS X");
    }


    String getPath(String command) {
        return getAppPath() + properties.getProperty(command);
    }

    protected String getAppPath() {
        return "";
    }

    protected File getConfigFilePath() {
        return new File("app/path.properties");
    }

    synchronized Properties loadAppProperties() {
        if (properties.isEmpty()) {
            File file = getConfigFilePath();

            if (file.exists()) {
                try (FileInputStream in = new FileInputStream(file)) {
                    properties.load(in);
                } catch (IOException e) {
                    logger.error("Error during loading properties", e);
                }
            } else {
                logger.error("Path properties is not found at: ", file.getPath());
            }
        }
        return properties;
    }

    //IMPORTANT !!!
    //using custom processes for Windows here -  Runtime.exec() due to JDK specific way of interpreting quoted arguments in ProcessBuilder https://bugs.openjdk.java.net/browse/JDK-8131908
    public Process createProcess(List<String> arguments) throws IOException {
        ProcessBuilder pb = new ProcessBuilder(arguments);
        return pb.start();
    }
}
