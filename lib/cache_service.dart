import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'models.dart';

/// 感知哈希持久化缓存：路径 -> {大小, 修改时间, 哈希, 宽高, 缩略图}
///
/// 仅在后台 isolate 中使用，故采用同步 IO；主 isolate 只负责传入缓存文件路径
class HashCache {
  final String algoName;
  final Map<String, Map<String, dynamic>> _entries;
  bool _dirty = false;

  HashCache._(this.algoName, this._entries);

  /// 从文件加载缓存；文件不存在、损坏或算法不匹配时返回空缓存
  static HashCache loadSync(String? filePath, String algoName) {
    if (filePath == null) return HashCache._(algoName, {});
    try {
      final file = File(filePath);
      if (!file.existsSync()) return HashCache._(algoName, {});
      final data = jsonDecode(file.readAsStringSync());
      if (data is Map && data['algo'] == algoName && data['entries'] is Map) {
        final entries =
            (data['entries'] as Map).cast<String, Map<String, dynamic>>();
        return HashCache._(algoName, entries);
      }
    } catch (_) {
      // 缓存损坏直接忽略，重建
    }
    return HashCache._(algoName, {});
  }

  /// 查询缓存：路径 + 大小 + 修改时间均匹配时返回图片信息
  ImageData? get(String path, int size, int mtimeMs) {
    final e = _entries[path];
    if (e == null) return null;
    if (e['s'] != size || e['m'] != mtimeMs) return null;
    try {
      return ImageData(
        path: path,
        name: p.basename(path),
        size: size,
        width: e['w'] as int,
        height: e['ht'] as int,
        hash: e['h'] as int,
        thumbnail: base64Decode(e['t'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// 写入/更新缓存条目
  void put(ImageData img, int mtimeMs) {
    _entries[img.path] = {
      's': img.size,
      'm': mtimeMs,
      'h': img.hash,
      'w': img.width,
      'ht': img.height,
      't': base64Encode(img.thumbnail),
    };
    _dirty = true;
  }

  /// 保存缓存到文件
  void saveSync(String? filePath) {
    if (!_dirty || filePath == null) return;
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
          jsonEncode({'algo': algoName, 'entries': _entries}));
      _dirty = false;
    } catch (_) {
      // 缓存保存失败不影响扫描结果
    }
  }
}
