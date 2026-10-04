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

# 保留注解/签名（ML Kit 与 Flutter 插件回调依赖）
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
