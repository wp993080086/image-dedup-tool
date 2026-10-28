import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 窗口状态持久化：保存/恢复窗口位置与大小
///
/// 启动恢复在 main() 中执行；关闭保存使用同步 IO——
/// 关闭回调中禁止平台通道调用（会死锁），故目录路径需提前缓存

/// 应用支持目录缓存（main 启动时初始化）
String? _supportDirPath;

/// 启动时缓存应用支持目录路径（供关闭时同步写文件使用）
Future<void> initWindowStateDir() async {
  try {
    final dir = await getApplicationSupportDirectory();
    _supportDirPath = dir.path;
  } catch (_) {
    _supportDirPath = null;
  }
}

String? _stateFilePath() {
  final dir = _supportDirPath;
  if (dir == null) return null;
  return p.join(dir, 'window_state.json');
}

/// 读取上次保存的窗口区域；无效或未保存时返回 null
Future<Rect?> loadWindowBounds() async {
  try {
    final path = _stateFilePath();
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final data = jsonDecode(file.readAsStringSync());
    if (data is! Map) return null;
    final rect = Rect.fromLTWH(
      (data['x'] as num).toDouble(),
      (data['y'] as num).toDouble(),
      (data['w'] as num).toDouble(),
      (data['h'] as num).toDouble(),
    );
    // 尺寸过小说明保存异常，回退默认窗口
    if (rect.width < 800 || rect.height < 600) return null;
    return rect;
  } catch (_) {
    return null;
  }
}

/// 同步保存窗口区域（关闭回调中使用，不做任何异步/平台通道调用）
void saveWindowBoundsSync(Rect bounds) {
  try {
    final path = _stateFilePath();
    if (path == null) return;
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({
      'x': bounds.left,
      'y': bounds.top,
      'w': bounds.width,
      'h': bounds.height,
    }));
  } catch (_) {
    // 保存失败不影响退出
  }
}
