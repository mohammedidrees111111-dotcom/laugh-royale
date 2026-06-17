# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ProGuard / R8 Rules — Laugh Royale (Release)
# These rules prevent crashes in production builds.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Flutter ──────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── Kotlin ───────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**

# ── Firebase ─────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Auth
-keepattributes Signature
-keep class com.google.firebase.auth.** { *; }
-keep class com.firebase.ui.auth.** { *; }
-dontwarn com.firebase.ui.auth.**

# Firebase Firestore
-keep class com.google.firebase.firestore.** { *; }
-dontwarn com.google.firebase.firestore.**

# Firebase Analytics
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.firebase.analytics.connector.** { *; }

# Firebase Crashlytics
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**

# ── ML Kit (if used) ─────────────────────────────────────
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# ── Google Play Services ─────────────────────────────────
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.**

# ── AdMob (if used) ──────────────────────────────────────
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# ── AndroidX ─────────────────────────────────────────────
-keep class androidx.** { *; }
-keep class * extends androidx.lifecycle.ViewModel { *; }
-dontwarn androidx.**

# ── WebRTC (if used) ─────────────────────────────────────
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ── WebRTC native JNI methods ────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class org.webrtc.voiceengine.** { *; }
-keep class org.webrtc.audio.** { *; }
-dontwarn org.webrtc.voiceengine.**
-keep class io.flutter.plugins.webrtc.** { *; }
-dontwarn io.flutter.plugins.webrtc.**

# ── Image/Media Libraries ────────────────────────────────
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# ── Reflection-based models ──────────────────────────────
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class * implements android.os.Parcelable { *; }

# ── Serializable ─────────────────────────────────────────
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── Native methods ───────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ── Enums ────────────────────────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── R classes ────────────────────────────────────────────
-keepclassmembers class **.R$* {
    public static <fields>;
}

# ── Suppress warnings ────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn java.lang.invoke.**
