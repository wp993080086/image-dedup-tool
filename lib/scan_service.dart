import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'cache_service.dart';
import 'models.dart';

/// 支持的图片扩展名
const imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'];

/// 候选相似对的最大汉明距离（对应相似度下限 50%：1 - 32/64 = 0.5）
///
/// 扫描阶段只收集距离 <= 该值的图片对；UI 改阈值后基于此结果在内存中二次过滤
const candidateMaxDistance = 32;

/// 感知哈希算法定义
class HashAlgorithm {
  final String name;

  /// 中文详情描述（UI 悬浮提示用）
  final String description;

  final int Function(img.Image src) calc;

  const HashAlgorithm(this.name, this.description, this.calc);
}

/// 算法列表（UI 下拉框按序号选择）
const hashAlgorithms = [
  HashAlgorithm(
    'pHash 感知哈希',
    '基于图像频率域（DCT 余弦变换）特征生成指纹，对缩放、压缩、轻微水印的抵抗力最强，速度稍慢，推荐作为默认算法。',
    _pHash,
  ),
  HashAlgorithm(
    'dHash 差异哈希',
    '比较相邻像素的亮暗梯度生成指纹，速度快，对亮度变化不敏感，综合表现均衡。',
    _dHash,
  ),
  HashAlgorithm(
    'aHash 均值哈希',
    '将图片压缩为 8x8 灰度图后与平均亮度比较生成指纹，速度最快，但精度一般，容易出现误判。',
    _aHash,
  ),
  HashAlgorithm(
    'mHash 中值哈希',
    '与均值哈希类似，但以亮度中位数为基准，抗局部亮度突变，精度介于 aHash 与 pHash 之间。',
    _mHash,
  ),
];

/// 后台扫描会话：提供进度回调与取消能力
class ScanSession {
  final ReceivePort _port;

  /// 协调者的取消通道（收到 'ready' 后可用）
  SendPort? _cancelSend;

  bool _finished = false;

  ScanSession(this._port);

  /// 取消扫描：通知协调者终止所有 worker 并自行退出
  void cancel() {
    if (_finished) return;
    _finished = true;
    _cancelSend?.send('cancel');
    _port.close();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _port.close();
  }

  /// 启动后台扫描
  ///
  /// [cachePath] 哈希缓存文件路径（null 表示不使用缓存）
  /// [onProgress] 进度回调（主 isolate 中执行）
  /// [onDone] 完成回调；[onError] 失败回调；取消后无任何回调
  static Future<ScanSession> start({
    required String folderPath,
    required bool recursive,
    required int algorithmIndex,
    String? cachePath,
    required void Function(ScanProgress) onProgress,
    required void Function(ScanResult) onDone,
    required void Function(String) onError,
  }) async {
    final port = ReceivePort();
    await Isolate.spawn(
      _scanEntry,
      _ScanParams(
          port.sendPort, folderPath, recursive, algorithmIndex, cachePath),
      errorsAreFatal: true,
    );
    final session = ScanSession(port);
    port.listen((message) {
      final type = message[0] as String;
      switch (type) {
        case 'ready':
          session._cancelSend = message[1] as SendPort;
        case 'progress':
          onProgress(message[1] as ScanProgress);
        case 'done':
          session._finish();
          onDone(message[1] as ScanResult);
        case 'error':
          session._finish();
          onError(message[1] as String);
      }
    });
    return session;
  }
}

/// 传给后台 isolate 的扫描参数
class _ScanParams {
  final SendPort toMain;
  final String folderPath;
  final bool recursive;
  final int algorithmIndex;

  /// 哈希缓存文件路径（null 表示不使用缓存）
  final String? cachePath;

  _ScanParams(this.toMain, this.folderPath, this.recursive, this.algorithmIndex,
      this.cachePath);
}

/// 后台协调 isolate 入口：缓存分流 -> 并行哈希 -> 两两比较
Future<void> _scanEntry(_ScanParams params) async {
  final stopwatch = Stopwatch()..start();
  // 收集 worker isolate，供取消时统一终止
  final spawnedWorkers = <Isolate>[];
  final cancelPort = ReceivePort();
  params.toMain.send(['ready', cancelPort.sendPort]);
  cancelPort.listen((msg) {
    if (msg == 'cancel') {
      for (final w in spawnedWorkers) {
        w.kill(priority: Isolate.immediate);
      }
      Isolate.exit();
    }
  });
  try {
    void sendProgress(String phase, int current, int total) {
      params.toMain.send(['progress', ScanProgress(phase, current, total)]);
    }

    // 1. 收集图片文件
    final files = _collectImageFiles(params.folderPath, params.recursive);
    if (files.length < 2) {
      params.toMain.send(['error', '所选文件夹中图片不足 2 张（当前 ${files.length} 张）']);
      return;
    }
    sendProgress('收集图片', files.length, files.length);

    // 2. 缓存分流：命中的直接构造，未命中的交给并行 worker
    final cache = HashCache.loadSync(
        params.cachePath, hashAlgorithms[params.algorithmIndex].name);
    final images = List<ImageData?>.filled(files.length, null);
    final pending = <File>[];
    var cacheHits = 0;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final stat = file.statSync();
      final cached =
          cache.get(file.path, stat.size, stat.modified.millisecondsSinceEpoch);
      if (cached != null) {
        images[i] = cached;
        cacheHits++;
      } else {
        pending.add(file);
      }
    }

    // 3. 并行处理未命中缓存的图片（worker 数量随 CPU 核数，上限 4）
    if (pending.isNotEmpty) {
      final workers = math.min(math.max(Platform.numberOfProcessors - 1, 2), 4);
      final batchSize = (pending.length / workers).ceil();
      final ports = <ReceivePort>[];
      final starts = <int>[];
      final futures = <Future<List<dynamic>>>[];
      var processed = 0;

      for (var start = 0; start < pending.length; start += batchSize) {
        final batch =
            pending.sublist(start, math.min(start + batchSize, pending.length));
        final port = ReceivePort();
        final completer = Completer<List<dynamic>>();
        port.listen((msg) {
          if (msg[0] == 'p') {
            processed += msg[1] as int;
            // 节流上报合并进度
            if (processed % 5 == 0 || processed >= pending.length) {
              sendProgress('解析图片', cacheHits + processed, files.length);
            }
          } else if (msg[0] == 'done') {
            port.close();
            completer.complete(msg[1] as List<dynamic>);
          }
        });
        final spawned = await Isolate.spawn(
            _hashWorker, [port.sendPort, batch, params.algorithmIndex]);
        spawnedWorkers.add(spawned);
        ports.add(port);
        starts.add(start);
        futures.add(completer.future);
      }

      // 按批次起始偏移写回结果
      final results = await Future.wait(futures);
      for (var b = 0; b < results.length; b++) {
        final list = results[b];
        for (var j = 0; j < list.length; j++) {
          final item = list[j] as List;
          final data = item[0] as ImageData?;
          if (data != null) {
            images[starts[b] + j] = data;
            cache.put(data, item[1] as int);
          }
        }
      }
    }

    // 4. 持久化缓存，过滤解码失败的图片
    cache.saveSync(params.cachePath);
    final validImages = images.whereType<ImageData>().toList();
    if (validImages.length < 2) {
      params.toMain.send(['error', '有效图片不足 2 张（部分图片可能无法解码）']);
      return;
    }

    // 5. 用 BK-tree 查找相似对，保留相似度 >= 50%（阈值滑块下限）的图片对
    //    结果与暴力两两比较完全一致，但通过汉明距离剪枝减少比较次数
    final tree = BKTree();
    for (var i = 0; i < validImages.length; i++) {
      tree.insert(validImages[i].hash, i);
    }
    final pairs = <SimilarPair>[];
    final totalPairs = validImages.length * (validImages.length - 1) ~/ 2;
    var donePairs = 0;
    for (var i = 0; i < validImages.length; i++) {
      // 查询距离 <= 32 的邻居，仅保留 j > i 的对，避免重复并保持与暴力循环一致的顺序
      final neighbors = tree.search(validImages[i].hash, candidateMaxDistance)
        ..removeWhere((j) => j <= i)
        ..sort();
      for (final j in neighbors) {
        final sim = _pairSimilarity(validImages[i].hash, validImages[j].hash);
        pairs.add(SimilarPair(i, j, sim));
      }
      donePairs += validImages.length - i - 1;
      if (i % 20 == 0 || i == validImages.length - 1) {
        sendProgress('对比哈希', donePairs > totalPairs ? totalPairs : donePairs,
            totalPairs);
      }
    }

    stopwatch.stop();
    params.toMain.send([
      'done',
      ScanResult(
          images: validImages,
          pairs: pairs,
          durationMs: stopwatch.elapsedMilliseconds),
    ]);
  } catch (e) {
    params.toMain.send(['error', '扫描失败：$e']);
  }
}

/// 并行哈希 worker：处理一批文件，逐张上报进度
void _hashWorker(List params) {
  final toCoordinator = params[0] as SendPort;
  final files = params[1] as List<File>;
  final hashFunc = hashAlgorithms[params[2] as int].calc;
  final out = <dynamic>[];
  for (final file in files) {
    final data = _processImage(file, hashFunc);
    var mtime = 0;
    try {
      mtime = file.lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {}
    out.add([data, mtime]);
    toCoordinator.send(['p', 1]);
  }
  toCoordinator.send(['done', out]);
}

/// 递归/非递归收集图片文件
List<File> _collectImageFiles(String folderPath, bool recursive) {
  final dir = Directory(folderPath);
  if (!dir.existsSync()) return [];
  final files = <File>[];
  for (final entity in dir.listSync(recursive: recursive, followLinks: false)) {
    if (entity is File) {
      final ext = p.extension(entity.path).toLowerCase();
      if (imageExtensions.contains(ext)) files.add(entity);
    }
  }
  // 按路径排序，保证结果顺序稳定
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// 处理单张图片：解码 -> 哈希 -> 缩略图；失败返回 null
ImageData? _processImage(File file, int Function(img.Image) hashFunc) {
  try {
    final bytes = file.readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final thumb = img.copyResize(image, width: 80);
    return ImageData(
      path: file.path,
      name: p.basename(file.path),
      size: bytes.length,
      width: image.width,
      height: image.height,
      hash: hashFunc(image),
      thumbnail: img.encodeJpg(thumb, quality: 80),
    );
  } catch (_) {
    // 单张失败不影响整体扫描
    return null;
  }
}

/// 计算两图哈希相似度（0-100）
double _pairSimilarity(int h1, int h2) {
  final dist = _popcount64(h1 ^ h2);
  // 线性口径：相似度 = 1 - 汉明距离占比，数值直观（90 表示 90% 的位相同）
  return (1 - dist / 64) * 100;
}

/// BK-tree：按 64 位汉明距离组织的索引，用于把相似对查找从 O(n²) 降下来
///
/// 每个节点保存一个哈希值及其对应的图片下标列表（同哈希可能有多张图），
/// 子节点按"与父节点哈希的汉明距离"分支。
/// 公开以便单元测试直接验证其正确性。
class BKTree {
  BKNode? _root;

  /// 插入一张图片的哈希与下标
  void insert(int hash, int index) {
    final root = _root;
    if (root == null) {
      _root = BKNode(hash, [index]);
      return;
    }
    var node = root;
    while (true) {
      final dist = _popcount64(node.hash ^ hash);
      if (dist == 0) {
        // 哈希完全相同，挂到同一节点
        node.indices.add(index);
        return;
      }
      final child = node.children[dist];
      if (child == null) {
        node.children[dist] = BKNode(hash, [index]);
        return;
      }
      node = child;
    }
  }

  /// 查询与给定哈希汉明距离 <= maxDistance 的所有图片下标
  ///
  /// 借助三角不等式剪枝：子节点距离落在 [dist - maxDistance, dist + maxDistance]
  /// 之外的分支不可能命中，直接跳过。
  List<int> search(int hash, int maxDistance) {
    final result = <int>[];
    final root = _root;
    if (root == null) return result;
    final stack = <BKNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final dist = _popcount64(node.hash ^ hash);
      if (dist <= maxDistance) result.addAll(node.indices);
      final low = dist - maxDistance;
      final high = dist + maxDistance;
      for (final entry in node.children.entries) {
        if (entry.key >= low && entry.key <= high) stack.add(entry.value);
      }
    }
    return result;
  }
}

/// BK-tree 节点
class BKNode {
  final int hash;

  /// 具有相同哈希的图片下标
  final List<int> indices;

  /// 子节点：key 为与当前节点哈希的汉明距离
  final Map<int, BKNode> children = {};

  BKNode(this.hash, this.indices);
}

/// 64-bit 汉明权重（位统计）
int _popcount64(int x) {
  x -= (x >> 1) & 0x5555555555555555;
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
  return ((x * 0x0101010101010101) & 0x7FFFFFFFFFFFFFFF) >> 56;
}

/// 取灰度像素值列表（按行优先）
List<int> _grayValues(img.Image image) {
  final pixels = <int>[];
  for (final pixel in image) {
    pixels.add(pixel.r.toInt());
  }
  return pixels;
}

/// aHash 均值哈希：8x8 灰度图与均值比较
int _aHash(img.Image src) {
  final g = img.copyResize(img.grayscale(src), width: 8, height: 8);
  final values = _grayValues(g);
  final mean = values.reduce((a, b) => a + b) / values.length;
  var hash = 0;
  for (final v in values) {
    hash = (hash << 1) | (v > mean ? 1 : 0);
  }
  return hash;
}

/// dHash 差异哈希：9x8 灰度图横向相邻像素比较
int _dHash(img.Image src) {
  final g = img.copyResize(img.grayscale(src), width: 9, height: 8);
  final values = _grayValues(g);
  var hash = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final left = values[y * 9 + x];
      final right = values[y * 9 + x + 1];
      hash = (hash << 1) | (left > right ? 1 : 0);
    }
  }
  return hash;
}

/// mHash 中值哈希：8x9 灰度图与中位数比较
int _mHash(img.Image src) {
  final g = img.copyResize(img.grayscale(src), width: 8, height: 9);
  final values = _grayValues(g);
  final sorted = List<int>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  final median = (sorted[mid - 1] + sorted[mid]) / 2;
  var hash = 0;
  for (final v in values) {
    hash = (hash << 1) | (v > median ? 1 : 0);
  }
  return hash;
}

/// pHash 感知哈希：32x32 DCT 低频 8x8 与均值比较
int _pHash(img.Image src) {
  final g = img.copyResize(img.grayscale(src), width: 32, height: 32);
  final values = _grayValues(g);
  const size = 32;

  // 构造亮度矩阵
  final matrix = List<List<double>>.generate(
    size,
    (y) => List<double>.generate(size, (x) => values[y * size + x].toDouble()),
  );

  // 行列各做一次一维 DCT
  final rows = List<List<double>>.generate(size, (y) => _dct(matrix[y]));
  final output = List<List<double>>.generate(
      size, (x) => _dct([for (var y = 0; y < size; y++) rows[y][x]]));

  // 取左上 8x8 低频分量
  final lowFreq = <double>[];
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      lowFreq.add(output[y][x]);
    }
  }

  // 去除第一个直流分量后取均值
  final rest = lowFreq.sublist(1);
  final mean = rest.reduce((a, b) => a + b) / rest.length;
  var hash = 0;
  for (final v in lowFreq) {
    hash = (hash << 1) | (v > mean ? 1 : 0);
  }
  return hash;
}

/// 32x32 DCT 余弦系数表（预计算避免重复三角函数运算）
final _dctTable = List<List<double>>.generate(
  32,
  (i) => List<double>.generate(
      32, (j) => math.cos((i * math.pi * (j + 0.5)) / 32)),
);
final _dctNorm = math.sqrt(2 / 32);

/// 一维离散余弦变换（32 点，使用预计算系数表）
List<double> _dct(List<double> input) {
  final out = List<double>.filled(32, 0);
  for (var i = 0; i < 32; i++) {
    var sum = 0.0;
    final coeff = _dctTable[i];
    for (var j = 0; j < 32; j++) {
      sum += input[j] * coeff[j];
    }
    sum *= _dctNorm;
    if (i == 0) sum *= 1 / math.sqrt(2);
    out[i] = sum;
  }
  return out;
}

/// 基于相似图片对，按阈值把图片聚合成相似组（并查集）
///
/// 组相似度取组内所有图片对的最低相似度；仅返回 >= 2 张图的组
List<SimilarGroup> groupByThreshold(
    List<ImageData> images, List<SimilarPair> pairs, double threshold) {
  final parent = List<int>.generate(images.length, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  // 组内最低相似度记录（根下标 -> min sim）
  final minSim = <int, double>{};
  for (final pair in pairs) {
    if (pair.similarity < threshold) continue;
    final ra = find(pair.indexA);
    final rb = find(pair.indexB);
    // 记录两端已有的最低相似度，再合并
    minSim[ra] = math.min(minSim[ra] ?? pair.similarity, pair.similarity);
    minSim[rb] = math.min(minSim[rb] ?? pair.similarity, pair.similarity);
    if (ra != rb) {
      parent[rb] = ra;
      minSim[ra] = math.min(minSim[ra]!, minSim[rb]!);
    }
  }

  // 按根分组
  final members = <int, List<int>>{};
  for (var i = 0; i < images.length; i++) {
    members.putIfAbsent(find(i), () => []).add(i);
  }

  final groups = <SimilarGroup>[];
  for (final entry in members.entries) {
    if (entry.value.length < 2) continue;
    final groupImages = entry.value.map((i) => images[i]).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    groups.add(SimilarGroup(
      images: groupImages,
      similarity: minSim[entry.key] ?? 100,
    ));
  }
  // 相似度高的组在前，同相似度按首图路径排序保证稳定
  groups.sort((a, b) {
    final cmp = b.similarity.compareTo(a.similarity);
    return cmp != 0 ? cmp : a.images.first.path.compareTo(b.images.first.path);
  });
  return groups;
}
