import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_dedup/scan_service.dart';

/// 参考实现：暴力两两比较，返回所有汉明距离 <= maxDistance 的 (i, j) 对（i < j）
List<List<int>> bruteForce(List<int> hashes, int maxDistance) {
  final pairs = <List<int>>[];
  for (var i = 0; i < hashes.length - 1; i++) {
    for (var j = i + 1; j < hashes.length; j++) {
      if (_popcount(hashes[i] ^ hashes[j]) <= maxDistance) {
        pairs.add([i, j]);
      }
    }
  }
  return pairs;
}

/// 待测实现：用 BKTree 生成 (i, j) 对（i < j），顺序与暴力实现一致
List<List<int>> viaBKTree(List<int> hashes, int maxDistance) {
  final tree = BKTree();
  for (var i = 0; i < hashes.length; i++) {
    tree.insert(hashes[i], i);
  }
  final pairs = <List<int>>[];
  for (var i = 0; i < hashes.length; i++) {
    final neighbors = tree.search(hashes[i], maxDistance)
      ..removeWhere((j) => j <= i)
      ..sort();
    for (final j in neighbors) {
      pairs.add([i, j]);
    }
  }
  return pairs;
}

/// 汉明权重（与源码同口径）
int _popcount(int x) {
  x -= (x >> 1) & 0x5555555555555555;
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
  return ((x * 0x0101010101010101) & 0x7FFFFFFFFFFFFFFF) >> 56;
}

/// 生成随机 64 位非负整数（拼两个 32 位随机数）
int _random64(Random rnd) => (rnd.nextInt(0x7FFFFFFF) << 32) | rnd.nextInt(0x7FFFFFFF);

void main() {
  group('BKTree 与暴力算法结果一致', () {
    test('随机哈希集，多种距离阈值', () {
      final rnd = Random(42);
      for (var round = 0; round < 20; round++) {
        final count = 2 + rnd.nextInt(40);
        final hashes = List<int>.generate(count, (_) => _random64(rnd));
        for (final maxDist in [0, 1, 5, 10, 32]) {
          expect(viaBKTree(hashes, maxDist), bruteForce(hashes, maxDist),
              reason: 'count=$count maxDist=$maxDist 结果不一致');
        }
      }
    });

    test('存在完全相同的哈希（同哈希多张图）', () {
      final hashes = [12345, 12345, 12345, 999, 12345 ^ 0x3];
      for (final maxDist in [0, 1, 2, 32]) {
        expect(viaBKTree(hashes, maxDist), bruteForce(hashes, maxDist));
      }
    });

    test('边界：空集与单元素', () {
      expect(viaBKTree([], 32), isEmpty);
      expect(viaBKTree([777], 32), isEmpty);
    });

    test('边界：极端哈希值 0 与全 1', () {
      final hashes = [0, 0x7FFFFFFFFFFFFFFF, 1, 0x7FFFFFFFFFFFFFFE];
      for (final maxDist in [0, 1, 32, 63, 64]) {
        expect(viaBKTree(hashes, maxDist), bruteForce(hashes, maxDist),
            reason: 'maxDist=$maxDist 结果不一致');
      }
    });

    test('候选阈值 32 下的结果与源码扫描口径一致', () {
      final rnd = Random(7);
      final hashes =
          List<int>.generate(60, (_) => _random64(rnd));
      expect(viaBKTree(hashes, candidateMaxDistance),
          bruteForce(hashes, candidateMaxDistance));
    });
  });
}
