import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 全局崩溃与未捕获错误日志：写入应用支持目录的 crash_log.txt
///
/// 应用崩溃后可把该文件发给开发者定位问题；日志超过 512KB 自动截断保留后半

/// 安装全局错误捕获（main 中调用一次）
void installErrorHandlers() {
  FlutterError.onError = (details) {
    logCrash('FlutterError: ${details.toString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logCrash('Uncaught: $error\n$stack');
    // 返回 false 交由默认处理，不吞错误
    return false;
  };
}

/// 追加一条日志
Future<void> logCrash(String message) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}crash_log.txt');
    final ts = DateTime.now().toIso8601String();
    await file.writeAsString('[$ts] $message\n\n', mode: FileMode.append);
    // 超限时保留后半部分
    if (await file.length() > 512 * 1024) {
      final content = await file.readAsString();
      await file.writeAsString(content.substring(content.length ~/ 2));
    }
  } catch (_) {
    // 日志失败不影响运行
  }
}
