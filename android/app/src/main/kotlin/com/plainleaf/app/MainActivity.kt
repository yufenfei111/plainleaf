package com.plainleaf.app

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * W14 应用锁：local_auth 的 Android 端走 AndroidX BiometricPrompt，
 * 要求宿主 Activity 是 FragmentActivity。用默认的 FlutterActivity
 * 会在真机点「用指纹解锁」时抛异常——被降级逻辑吞成"设备不支持指纹"，
 * 表现是功能静默不可用，且只在真机上才发现（本机 flutter test 走不到这条路）。
 */
class MainActivity : FlutterFragmentActivity()
