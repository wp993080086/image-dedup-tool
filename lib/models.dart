import 'dart:typed_data';

/// 单张图片信息（含感知哈希与缩略图）
class ImageData {
  /// 图片完整路径
  final String path;

  /// 文件名
  final String name;

  /// 文件大小（字节）
  final int size;

  /// 图片宽
  final int width;

  /// 图片高
  final int height;

  /// 64-bit 感知哈希
  final int hash;

  /// 宽 80px 的 JPEG 缩略图字节
  final Uint8List thumbnail;

  ImageData({
    required this.path,
    required this.name,
    required this.size,
    required this.width,
    required this.height,
    required this.hash,
    required this.thumbnail,
  });
}

/// 相似图片对（哈希比较产物，用于按阈值重新分组）
class SimilarPair {
  /// 图片在列表中的下标
  final int indexA;
  final int indexB;

  /// 相似度（0-100，越高越相似）
  final double similarity;

  SimilarPair(this.indexA, this.indexB, this.similarity);
}

/// 相似图片组（互相相似的图片聚合）
class SimilarGroup {
  /// 组内图片（按路径排序）
  final List<ImageData> images;

  /// 组内最低相似度（0-100）
  final double similarity;

  SimilarGroup({
    required this.images,
    required this.similarity,
  });
}

/// 扫描结果
class ScanResult {
  /// 参与对比的全部图片
  final List<ImageData> images;

  /// 相似图片对列表（相似度 >= 保留阈值）
  final List<SimilarPair> pairs;

  /// 扫描总耗时（毫秒）
  final int durationMs;

  ScanResult({
    required this.images,
    required this.pairs,
    required this.durationMs,
  });
}

/// 扫描进度
class ScanProgress {
  /// 阶段文案，例如"解析图片"
  final String phaseText;

  /// 当前进度
  final int current;

  /// 总量
  final int total;

  ScanProgress(this.phaseText, this.current, this.total);
}
