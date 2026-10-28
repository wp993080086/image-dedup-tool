import 'dart:ui';

/// 相似度徽章配色（越高越绿的语义色）
Color similarityColor(double similarity) {
  if (similarity >= 95) return const Color(0xFF047857);
  if (similarity >= 85) return const Color(0xFF059669);
  if (similarity >= 75) return const Color(0xFFD97706);
  return const Color(0xFFDC2626);
}

/// 格式化文件大小显示
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

/// 格式化扫描耗时
String formatScanTime(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  if (seconds < 60) return '$seconds 秒';
  return '${seconds ~/ 60} 分 ${seconds % 60} 秒';
}
