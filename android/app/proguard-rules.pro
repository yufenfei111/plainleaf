# 素页 PlainLeaf · Release 混淆规则（W16 发布准备）
#
# R8 默认会把未被"直接引用"的类裁掉。Flutter 插件的注册与调用跨越 Java/Dart 边界，
# 部分路径依赖反射与字符串查找，因此需要显式保留。
#
# 注意：本文件只在 `isMinifyEnabled = true` 的 release 构建里生效。
# 规则写错的典型症状是"构建成功、装上就崩"（ClassNotFoundException / NoSuchMethodError），
# 所以**每次改动这里都必须用 release 包真机跑一轮主链路**，不能只看构建是否通过。

# ---- Flutter 引擎与嵌入层 ----
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---- 本项目用到的插件（W13–W15 新增的四个平台通道依赖优先）----
# local_auth：AndroidX BiometricPrompt 走反射调用
-keep class androidx.biometric.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }

# flutter_secure_storage：凭据与密钥存储
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# gal：保存图片到系统相册
-keep class studio.midoridesign.gal.** { *; }

# path_provider / image_picker：文件与选择器通道
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }

# ---- sqlite3 / Drift（经由 JNI 调用 native 库）----
-keep class com.tekartik.sqflite.** { *; }

# ---- 保留行号 ----
# 开混淆后堆栈会变成 a.b.c，没有行号基本无法定位线上崩溃。
# 这里保留源文件名与行号，代价是包体略增、反编译稍容易。
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ---- 通用：Tink / 密码学（cryptography 为纯 Dart，但 secure_storage 链上可能有 JCE）----
-dontwarn javax.annotation.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
