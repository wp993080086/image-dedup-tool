import 'dart:async';
import 'dart:io' show exit;

import 'package:image_dedup/app_state.dart';
import 'package:image_dedup/crash_log.dart';
import 'package:image_dedup/home.dart';
import 'package:image_dedup/window_state.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 全局导航 key（关闭确认弹窗使用）
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 全局按钮鼠标光标：可用时显示手型，禁用时显示禁用光标
final buttonMouseCursor = WidgetStateProperty.resolveWith<MouseCursor>(
  (states) => states.contains(WidgetState.disabled)
      ? SystemMouseCursors.forbidden
      : SystemMouseCursors.click,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 捕获全局错误写入本地日志，便于崩溃后定位
  installErrorHandlers();
  await initWindowStateDir();
  await windowManager.ensureInitialized();

  // 恢复上次窗口位置与大小
  final saved = await loadWindowBounds();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: saved?.size ?? const Size(1280, 780),
      minimumSize: const Size(1024, 640),
      title: '图片去重',
      center: saved == null,
    ),
    () async {
      // WindowOptions 在 0.4.x 不支持 position，单独设置
      if (saved != null) {
        await windowManager.setBounds(saved);
      }
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // 拦截关闭事件：关闭回调中不做平台通道调用（会死锁），窗口状态靠拖动/缩放时缓存
  final guard = _WindowGuard();
  guard.initBounds(saved);
  await windowManager.setPreventClose(true);

  runApp(const MyApp());
}

/// 窗口状态守护：拖动/缩放时节流缓存窗口区域，关闭时同步写盘并立即销毁
class _WindowGuard with WindowListener {
  /// 最近一次已知的窗口区域（启动时初始化为恢复值）
  Rect? _lastBounds;

  /// 节流定时器（拖动/缩放期间 getBounds 调用频繁）
  Timer? _throttle;

  bool _closing = false;

  /// 启动时记录恢复的窗口区域
  void initBounds(Rect? initial) {
    _lastBounds = initial;
    windowManager.addListener(this);
  }

  @override
  void onWindowMove() => _scheduleCacheBounds();

  @override
  void onWindowResize() => _scheduleCacheBounds();

  void _scheduleCacheBounds() {
    if (_closing) return;
    _throttle?.cancel();
    // fire-and-forget：不阻塞事件回调，仅更新内存缓存
    _throttle = Timer(const Duration(milliseconds: 300), () {
      windowManager.getBounds().then((b) => _lastBounds = b);
    });
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _throttle?.cancel();

    // 扫描进行中：先弹确认框（纯 UI 操作，无平台通道调用，不会死锁）
    if (isScanning.value) {
      final ctx = navigatorKey.currentContext;
      final quit = ctx == null
          ? true
          : await showDialog<bool>(
              context: ctx,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('扫描尚未完成'),
                content: const Text('退出将中断本次扫描，已扫描的进度不会保存。\n\n确定退出吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('继续扫描'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                    child: const Text('退出'),
                  ),
                ],
              ),
            );
      if (quit != true) return; // 用户选择继续扫描，窗口保持
    }

    _closing = true;
    final b = _lastBounds;
    if (b != null) saveWindowBoundsSync(b);
    // 状态已落盘；preventClose 下 destroy 无法保证进程退出，直接终止
    exit(0);
  }
}

/// 主应用类，设置浅色简洁主题与首页
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 统一应用到各类按钮的样式（仅设置光标，其余保持默认）
    ButtonStyle cursorStyle() => ButtonStyle(mouseCursor: buttonMouseCursor);
    return MaterialApp(
      title: '图片去重',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        splashFactory: InkSparkle.splashFactory,
        elevatedButtonTheme: ElevatedButtonThemeData(style: cursorStyle()),
        filledButtonTheme: FilledButtonThemeData(style: cursorStyle()),
        textButtonTheme: TextButtonThemeData(style: cursorStyle()),
        outlinedButtonTheme: OutlinedButtonThemeData(style: cursorStyle()),
        iconButtonTheme: IconButtonThemeData(style: cursorStyle()),
        segmentedButtonTheme: SegmentedButtonThemeData(style: cursorStyle()),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
