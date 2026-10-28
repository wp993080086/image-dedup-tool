import 'package:flutter/foundation.dart';

/// 全局应用状态
///
/// 是否正在扫描：关闭窗口拦截据此决定是否弹出确认框（home 页负责更新）
final ValueNotifier<bool> isScanning = ValueNotifier<bool>(false);
