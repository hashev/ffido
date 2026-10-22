# shared_preferences 2.5 uses JNI lookups with literal JVM descriptors.
# @Keep preserves registrars but not their descriptor classes (in particular
# kotlin.coroutines.Continuation); renaming those breaks release startup.
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.SharedPreferencesApiRegistrar { *; }
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.SharedPreferencesAsyncApiRegistrar { *; }
# package:jni 1.1 accesses these Kotlin runtime symbols by name as well.
-keep,includedescriptorclasses interface kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
