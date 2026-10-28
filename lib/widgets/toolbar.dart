import 'package:image_dedup/scan_service.dart';
import 'package:flutter/material.dart';

/// 顶部工具栏（左右布局）：左侧算法/阈值，右侧路径与操作
class ToolbarWidget extends StatelessWidget {
  final String? folderPath;
  final int algorithmIndex;
  final ValueChanged<int> onAlgorithmChanged;
  final bool recursive;
  final ValueChanged<bool> onRecursiveChanged;
  final double threshold;
  final ValueChanged<double> onThresholdChanged;
  final bool scanning;
  final VoidCallback onStartScan;
  final VoidCallback onCancelScan;
  final VoidCallback onInit;
  final bool showCleanup;
  final VoidCallback onDeleteAllExtras;
  final VoidCallback onHelp;

  const ToolbarWidget({
    super.key,
    required this.folderPath,
    required this.algorithmIndex,
    required this.onAlgorithmChanged,
    required this.recursive,
    required this.onRecursiveChanged,
    required this.threshold,
    required this.onThresholdChanged,
    required this.scanning,
    required this.onStartScan,
    required this.onCancelScan,
    required this.onInit,
    required this.showCleanup,
    required this.onDeleteAllExtras,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ===== 左栏：第一行算法，第二行阈值 =====
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 算法单选框
                    Row(
                      children: [
                        const Text('算法', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        const SizedBox(width: 8),
                        IgnorePointer(
                          ignoring: scanning,
                          child: Opacity(
                            opacity: scanning ? 0.5 : 1.0,
                            child: RadioGroup<int>(
                              groupValue: algorithmIndex,
                              onChanged: (v) {
                                if (v != null) onAlgorithmChanged(v);
                              },
                              child: Row(
                                children: [
                                  for (var i = 0; i < hashAlgorithms.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Tooltip(
                                        message: hashAlgorithms[i].description,
                                        waitDuration: const Duration(milliseconds: 300),
                                        margin: const EdgeInsets.symmetric(horizontal: 24),
                                        child: InkWell(
                                          onTap: () => onAlgorithmChanged(i),
                                          mouseCursor: SystemMouseCursors.click,
                                          borderRadius: BorderRadius.circular(6),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 2, vertical: 2),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: Radio<int>(
                                                    value: i,
                                                    // RadioGroup 模式下 Radio 无 onChanged 会被视为禁用，
                                                    // 显式指定手型光标
                                                    mouseCursor: SystemMouseCursors.click,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  hashAlgorithms[i].name.split(' ').first,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: algorithmIndex == i
                                                        ? const Color(0xFF2563EB)
                                                        : const Color(0xFF374151),
                                                    fontWeight: algorithmIndex == i
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 阈值滑块
                    Row(
                      children: [
                        Tooltip(
                          message: '相似度低于该阈值的图片不会被归为相似组。\n'
                              '注意：扫描时统一按 50% 收集候选对，'
                              '阈值越高（如 85% 以上）剪枝效果越好、扫描越快；'
                              '阈值越低（接近 50%）候选对越多，扫描越慢。',
                          child: const Text('相似阈值',
                              style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 180,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              activeTrackColor: scheme.primary,
                              inactiveTrackColor: Colors.grey[200],
                              thumbColor: Colors.white,
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              overlayColor: scheme.primary.withValues(alpha: 0.12),
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8, elevation: 2),
                            ),
                            child: Slider(
                              min: 50,
                              max: 100,
                              divisions: 50,
                              value: threshold,
                              label: '${threshold.toStringAsFixed(0)}%',
                              mouseCursor: SystemMouseCursors.click,
                              onChanged: onThresholdChanged,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${threshold.toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                // ===== 右栏：第一行路径+开关，第二行操作按钮（右对齐）=====
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 第一行：路径 + 含子文件夹（紧凑分组，间距 12）
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (folderPath != null)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.folder,
                                      size: 16, color: Color(0xFF2563EB)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Tooltip(
                                      message: folderPath!,
                                      child: Text(
                                        folderPath!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13, color: Color(0xFF374151)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 36,
                            child: Row(
                              children: [
                                Switch(
                                  value: recursive,
                                  onChanged: scanning ? null : onRecursiveChanged,
                                  mouseCursor: SystemMouseCursors.click,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                const Text('含子文件夹', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 第二行：操作按钮（右对齐，窄窗口自动换行）
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runAlignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // 扫描 / 取消
                          if (!scanning)
                            FilledButton.icon(
                              onPressed: folderPath == null ? null : onStartScan,
                              icon: const Icon(Icons.radar, size: 18),
                              label: const Text('开始扫描'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: onCancelScan,
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('取消'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                            ),

                          // 初始化：清空结果回到初始状态，可继续扫描
                          OutlinedButton.icon(
                            onPressed: scanning ? null : onInit,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('初始化'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF374151),
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),

                          // 一键清理：删除所有相似组的多余图片（每组保留 1 张）
                          if (showCleanup)
                            OutlinedButton.icon(
                              onPressed: scanning ? null : onDeleteAllExtras,
                              icon: const Icon(Icons.auto_delete, size: 18),
                              label: const Text('一键清理'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(color: Color(0xFFDC2626)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),

                          IconButton(
                            onPressed: onHelp,
                            icon: const Icon(Icons.help_outline, size: 20),
                            tooltip: '使用说明',
                            color: Colors.grey[600],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }
}

/// 使用说明弹窗内容
class HelpDialogContent extends StatelessWidget {
  const HelpDialogContent({super.key});

  Widget _dot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('使用步骤', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('1. 选择待检测的图片文件夹（可含子文件夹）'),
          const Text('2. 悬浮"算法"单选框可查看算法中文说明，选好后点击"开始扫描"'),
          const Text('3. 调整相似阈值，实时筛选相似组'),
          const Text('4. 点击左侧相似组，右侧查看大图对比'),
          const Text('5. 删除：预览图右上角删除按钮删除单张；"删除本组多余图片"/"一键清理"每组保留 1 张（移入回收站可还原）'),
          const SizedBox(height: 14),
          const Text('相似度说明', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('相似度 = 哈希相同位数占比，100% 表示完全一致。默认阈值 85%，阈值越高判定越严格。'),
          const SizedBox(height: 14),
          const Text('算法说明（与悬浮提示一致）', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final algo in hashAlgorithms) ...[
            Text(
              '· ${algo.name.split(' ').first}：${algo.description}',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 10),
          const Text('相似度徽章颜色', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [_dot(const Color(0xFF047857)), const SizedBox(width: 8), const Text('≥95% 极高相似')]),
          const SizedBox(height: 4),
          Row(children: [_dot(const Color(0xFF059669)), const SizedBox(width: 8), const Text('85%~95% 高相似')]),
          const SizedBox(height: 4),
          Row(children: [_dot(const Color(0xFFD97706)), const SizedBox(width: 8), const Text('75%~85% 疑似相似')]),
          const SizedBox(height: 4),
          Row(children: [_dot(const Color(0xFFDC2626)), const SizedBox(width: 8), const Text('<75% 弱相似')]),
          const SizedBox(height: 8),
          Text('徽章显示的是组内最低相似度', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }
}
