# ===== ML Kit text recognition（R8 裁剪/混淆兼容）=====
# 关键：Dart 侧通过 MethodChannel 字符串反射创建识别器，R8 静态分析看不到引用链，
# 会把"未引用"的 chinese/devanagari/japanese/korean 识别器类整个裁掉，
# 导致运行时 ClassNotFoundException 崩溃。必须显式 keep 所有脚本的识别器包。
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.common.internal.** { *; }
-keep class com.google.android.gms.dynamic.** { *; }
-keep class com.google.android.libraries.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# ===== Vosk/JNA 离线语音识别（R8 兼容）=====
# 关键：JNA 通过 native 方法（initIDs 等）与"字段 ID"绑定原生库，
# R8 的优化/混淆会破坏该绑定，运行时抛
# UnsatisfiedLinkError: Can't obtain peer field ID for com.sun.jna.Pointer。
# 必须 keep JNA 全部类与 vosk 桥接类（vosk 经 JNA 反射访问原生结构）。
-keep class com.sun.jna.** { *; }
-keep class org.vosk.** { *; }
-keepclassmembers class * implements com.sun.jna.Callback { *; }
-dontwarn com.sun.jna.**
-dontwarn org.vosk.**

# 保留注解/签名（ML Kit 与 Flutter 插件回调依赖）
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
