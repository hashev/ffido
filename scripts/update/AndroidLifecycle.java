// Test-only helper for a rootable disposable emulator; never packaged in FFIDO.
import java.lang.reflect.Method;

public final class AndroidLifecycle {
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !(args[0].equals("true") || args[0].equals("false"))) {
            throw new IllegalArgumentException("Expected true or false");
        }
        Class<?> manager;
        Method getter;
        try {
            manager = Class.forName("android.app.ActivityManagerNative");
            getter = manager.getDeclaredMethod("getDefault");
        } catch (ClassNotFoundException | NoSuchMethodException oldApi) {
            manager = Class.forName("android.app.ActivityManager");
            getter = manager.getDeclaredMethod("getService");
        }
        getter.setAccessible(true);
        Object service = getter.invoke(null);
        Method setter = service.getClass().getDeclaredMethod("setAlwaysFinish", boolean.class);
        setter.setAccessible(true);
        setter.invoke(service, Boolean.parseBoolean(args[0]));
        System.out.println("always_finish=" + args[0]);
    }
}
