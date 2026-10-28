import 'dart:io';

import 'package:image_dedup/app_state.dart';
import 'package:image_dedup/models.dart';
import 'package:image_dedup/recycle_bin.dart';
import 'package:image_dedup/scan_service.dart';
import 'package:image_dedup/utils.dart';
import 'package:image_dedup/widgets/group_list.dart';
import 'package:image_dedup/widgets/group_preview.dart';
import 'package:image_dedup/widgets/toolbar.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片相似度检测主页面
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 已选择的扫描文件夹
  String? folderPath;

  /// 当前哈希算法下标
  int algorithmIndex = 0;

  /// 是否包含子文件夹
  bool recursive = true;

  /// 相似阈值（50-100，相似度百分比）
  double threshold = 85;

  /// 是否正在扫描
  bool scanning = false;

  /// 扫描进度
  ScanProgress? progress;

  /// 后台扫描会话
  ScanSession? _session;

  /// 扫描结果（图片 + 相似对）
  ScanResult? _result;

  /// 按当前阈值分组后的相似组
  List<SimilarGroup> groups = [];

  /// 左侧页签：0=相似组，1=已删除
  int listTab = 0;

  /// 多选删除模式
  bool _multiSelect = false;

  /// 多选模式下勾选的组下标
  final Set<int> _selectedGroups = {};

  /// "相似度低于 N%" 批量选中的输入
  final TextEditingController _simBelowCtrl = TextEditingController(text: '75');

  /// 本次会话已删除的图片（供"已删除"页签展示）
  final List<ImageData> _deletedImages = [];

  /// 当前选中的组下标
  int? selectedGroup;

  /// 本次会话累计删除的图片数
  int deletedCount = 0;

  /// 错误提示
  String? errorMessage;

  /// 是否有文件夹拖入窗口上方（高亮提示）
  bool _dragOver = false;

  @override
  void dispose() {
    _session?.cancel();
    _simBelowCtrl.dispose();
    super.dispose();
  }

  /// 选择扫描文件夹
  Future<void> _pickFolder() async {
    final path = await getDirectoryPath();
    if (path != null) {
      setState(() {
        folderPath = path;
        _result = null;
        groups = [];
        selectedGroup = null;
        _deletedImages.clear();
        listTab = 0;
        deletedCount = 0;
        errorMessage = null;
      });
    }
  }

  /// 启动后台扫描
  Future<void> _startScan() async {
    final path = folderPath;
    if (path == null || scanning) return;
    // 获取哈希缓存文件路径（平台通道只能在主 isolate 调用）
    String? cachePath;
    try {
      final dir = await getApplicationSupportDirectory();
      cachePath = p.join(dir.path, 'hash_cache.json');
    } catch (_) {}
    setState(() {
      scanning = true;
      isScanning.value = true;
      progress = null;
      _result = null;
      groups = [];
      selectedGroup = null;
      _deletedImages.clear();
      listTab = 0;
      deletedCount = 0;
      errorMessage = null;
    });
    _session = await ScanSession.start(
      folderPath: path,
      recursive: recursive,
      algorithmIndex: algorithmIndex,
      cachePath: cachePath,
      onProgress: (p) {
        if (mounted && scanning) setState(() => progress = p);
      },
      onDone: (result) {
        if (!mounted) return;
        setState(() {
          scanning = false;
          isScanning.value = false;
          progress = null;
          _result = result;
          _regroup();
        });
        if (groups.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('扫描完成，未发现相似图片'),
                behavior: SnackBarBehavior.floating),
          );
        }
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          scanning = false;
          isScanning.value = false;
          progress = null;
          errorMessage = msg;
        });
      },
    );
  }

  /// 取消扫描
  void _cancelScan() {
    _session?.cancel();
    _session = null;
    setState(() {
      scanning = false;
      isScanning.value = false;
      progress = null;
    });
  }

  /// 初始化：清空扫描结果回到初始状态（保留文件夹/算法/阈值，方便继续扫描）
  void _reset() {
    setState(() {
      _result = null;
      groups = [];
      selectedGroup = null;
      _deletedImages.clear();
      listTab = 0;
      deletedCount = 0;
      errorMessage = null;
      progress = null;
    });
  }

  /// 按当前阈值重新分组（纯内存运算，瞬时完成）
  void _regroup() {
    final result = _result;
    if (result == null) {
      groups = [];
      return;
    }
    groups = groupByThreshold(result.images, result.pairs, threshold);
    // 选中项越界时重置
    if (selectedGroup != null && selectedGroup! >= groups.length) {
      selectedGroup = groups.isEmpty ? null : 0;
    }
  }

  /// 从扫描结果中移除指定旧下标的图片，并重映射相似对下标
  void _removeImagesByIndices(Set<int> oldIndices) {
    final result = _result;
    if (result == null) return;
    final newImages = <ImageData>[];
    final oldToNew = <int, int>{};
    for (var i = 0; i < result.images.length; i++) {
      final img = result.images[i];
      if (oldIndices.contains(i)) {
        // 记录到"已删除"页签
        _deletedImages.add(img);
      } else {
        oldToNew[i] = newImages.length;
        newImages.add(img);
      }
    }
    final newPairs = result.pairs
        .where((p) =>
            oldToNew.containsKey(p.indexA) && oldToNew.containsKey(p.indexB))
        .map((p) =>
            SimilarPair(oldToNew[p.indexA]!, oldToNew[p.indexB]!, p.similarity))
        .toList();
    _result = ScanResult(
        images: newImages, pairs: newPairs, durationMs: result.durationMs);
    deletedCount += oldIndices.length;
    _regroup();
  }

  /// 删除确认弹窗（移入回收站）
  Future<bool> _confirmDelete(String title, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    return res == true;
  }

  /// 删除单张图片
  Future<void> _deleteImage(ImageData image) async {
    if (scanning || _result == null) return;
    // 提前获取 messenger，避免 async gap 后使用 context
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirmDelete(
        '删除图片', '确定将 "${image.name}" 移入回收站吗？\n\n可从系统回收站还原。');
    if (!ok || !mounted) return;
    final failed = await deleteFilesToRecycleBin([image.path]);
    if (!mounted) return;
    if (failed.isNotEmpty) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('删除失败：文件可能被占用'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    // 从结果中定位该图片的旧下标
    final idx = _result!.images.indexWhere((e) => e.path == image.path);
    if (idx < 0) return;
    setState(() => _removeImagesByIndices({idx}));
    messenger.showSnackBar(
      SnackBar(
          content: Text('已移入回收站：${image.name}'),
          behavior: SnackBarBehavior.floating),
    );
  }

  /// 删除指定组的多余图片（每组保留第 1 张）；groupIndices 为 null 时清理全部组
  Future<void> _deleteExtras({List<int>? groupIndices}) async {
    if (scanning || _result == null || groups.isEmpty) return;
    final scope = groupIndices == null
        ? groups
        : [
            for (final i in groupIndices)
              if (i >= 0 && i < groups.length) groups[i]
          ];
    // 收集待删图片（组间无共享图片，不会重复）
    final toDelete = [for (final g in scope) ...g.images.skip(1)];
    if (toDelete.isEmpty) return;
    final keepCount = scope.length;
    final scopeText = groupIndices == null
        ? '全部 ${groups.length} 个相似组'
        : '所选 ${scope.length} 个相似组';
    final ok = await _confirmDelete(
      groupIndices == null ? '一键清理' : '删除所选组多余图片',
      '将把 $scopeText 中的 ${toDelete.length} 张多余图片移入回收站，每组保留 1 张（共保留 $keepCount 张）。\n\n'
      '待删除示例：${toDelete.take(3).map((e) => e.name).join('、')}${toDelete.length > 3 ? ' 等' : ''}\n\n可从系统回收站还原。',
    );
    if (!ok || !mounted) return;

    // 批量移入回收站（单次系统调用）
    final messenger = ScaffoldMessenger.of(context);
    final failedSet =
        (await deleteFilesToRecycleBin(toDelete.map((e) => e.path).toList()))
            .toSet();
    if (!mounted) return;
    final deletedIndices = <int>{};
    for (var i = 0; i < _result!.images.length; i++) {
      if (toDelete.any((e) => e.path == _result!.images[i].path) &&
          !failedSet.contains(_result!.images[i].path)) {
        deletedIndices.add(i);
      }
    }
    if (deletedIndices.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('删除失败：文件可能被占用'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _removeImagesByIndices(deletedIndices));
    // 清空多选（组下标已失效）
    _selectedGroups.clear();
    messenger.showSnackBar(
      SnackBar(
        content: Text(failedSet.isEmpty
            ? '已移入回收站 ${deletedIndices.length} 张图片'
            : '已移入回收站 ${deletedIndices.length} 张，${failedSet.length} 张失败（文件可能被占用）'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 多选操作条：全选、按相似度批量选中、删除所选
  Widget _buildMultiSelectBar() {
    final allSelected =
        groups.isNotEmpty && _selectedGroups.length == groups.length;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                height: 22,
                width: 22,
                child: Checkbox(
                  value: allSelected,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedGroups
                        ..clear()
                        ..addAll([for (var i = 0; i < groups.length; i++) i]);
                    } else {
                      _selectedGroups.clear();
                    }
                  }),
                  mouseCursor: SystemMouseCursors.click,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              const Text('全选', style: TextStyle(fontSize: 13)),
              const Spacer(),
              const Text('相似度低于',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 4),
              SizedBox(
                width: 48,
                child: TextField(
                  controller: _simBelowCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    // 限制 0~100
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final n = int.tryParse(newValue.text);
                      if (n == null || n > 100) return oldValue;
                      return newValue;
                    }),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  ),
                  onSubmitted: (_) => _selectBelow(),
                ),
              ),
              const Text('%',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              TextButton(
                onPressed: _selectBelow,
                child: const Text('选中', style: TextStyle(fontSize: 13)),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _multiSelect = false;
                  _selectedGroups.clear();
                }),
                icon: const Icon(Icons.close, size: 18),
                tooltip: '退出多选',
                mouseCursor: SystemMouseCursors.click,
                color: Colors.grey[600],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selectedGroups.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.auto_delete, size: 16),
              label: Text(
                _selectedGroups.isEmpty
                    ? '请先勾选要清理的相似组'
                    : '删除所选 ${_selectedGroups.length} 组的多余图片（每组保留 1 张）',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 批量选中相似度低于 N% 的组
  void _selectBelow() {
    final n = double.tryParse(_simBelowCtrl.text);
    if (n == null) return;
    setState(() {
      _selectedGroups
        ..clear()
        ..addAll([
          for (var i = 0; i < groups.length; i++)
            if (groups[i].similarity < n) i,
        ]);
    });
  }

  /// 删除多选勾选的组
  void _deleteSelected() {
    if (_selectedGroups.isEmpty) return;
    _deleteExtras(groupIndices: _selectedGroups.toList());
  }

  /// 显示使用说明
  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用说明'),
        content: SizedBox(
          width: 440,
          child: const HelpDialogContent(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 拖入文件夹到窗口：取第一个文件夹路径作为扫描目录
  void _onDragDone(DropDoneDetails details) {
    setState(() => _dragOver = false);
    if (scanning) return;
    for (final file in details.files) {
      final path = file.path;
      if (Directory(path).existsSync()) {
        setState(() {
          folderPath = path;
          _result = null;
          groups = [];
          selectedGroup = null;
          _deletedImages.clear();
          listTab = 0;
          deletedCount = 0;
          errorMessage = null;
        });
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('请拖入文件夹（而非文件）'), behavior: SnackBarBehavior.floating),
    );
  }

  /// 底部空状态提示文案
  String get _emptyHint {
    if (errorMessage != null) return errorMessage!;
    if (scanning) return '正在扫描…';
    if (folderPath == null) return '把图片文件夹拖进窗口，\n或点击下方按钮选择，再点击顶部"开始扫描"';
    return '点击顶部"开始扫描"检测相似图片';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      body: SafeArea(
        // 支持把文件夹直接拖进窗口
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragOver = true),
          onDragExited: (_) => setState(() => _dragOver = false),
          onDragDone: _onDragDone,
          child: Container(
            // 拖入高亮边框（foreground 不影响布局）
            foregroundDecoration: BoxDecoration(
              border: _dragOver
                  ? Border.all(color: const Color(0xFF2563EB), width: 4)
                  : const Border(),
            ),
            child: Column(
              children: [
                ToolbarWidget(
                  folderPath: folderPath,
                  algorithmIndex: algorithmIndex,
                  onAlgorithmChanged: (v) => setState(() => algorithmIndex = v),
                  recursive: recursive,
                  onRecursiveChanged: (v) => setState(() => recursive = v),
                  threshold: threshold,
                  onThresholdChanged: (v) {
                    setState(() {
                      threshold = v;
                      _regroup();
                    });
                  },
                  scanning: scanning,
                  onStartScan: _startScan,
                  onCancelScan: _cancelScan,
                  onInit: _reset,
                  showCleanup: groups.isNotEmpty,
                  onDeleteAllExtras: () => _deleteExtras(),
                  onHelp: _showHelp,
                ),
                Expanded(
                  child: result == null && !scanning
                      ? _EmptyState(
                          hint: _emptyHint,
                          isError: errorMessage != null,
                          folderPath: folderPath,
                          onPickFolder: _pickFolder,
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左侧相似组列表（约占 40%）
                            Expanded(
                              flex: 4,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                      right:
                                          BorderSide(color: Colors.grey[200]!)),
                                ),
                                child: scanning
                                    ? _ScanningHint(progress: progress)
                                    : Column(
                                        children: [
                                          // 页签行 / 多选操作条
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                12, 12, 12, 0),
                                            child: _multiSelect
                                                ? _buildMultiSelectBar()
                                                : Row(
                                                    children: [
                                                      Expanded(
                                                        child: SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child:
                                                              SegmentedButton<
                                                                  int>(
                                                            segments: [
                                                              ButtonSegment(
                                                                value: 0,
                                                                label: Text(
                                                                    '相似组 ${groups.length}'),
                                                              ),
                                                              ButtonSegment(
                                                                value: 1,
                                                                label: Text(
                                                                    '已删除 ${_deletedImages.length}'),
                                                              ),
                                                            ],
                                                            selected: {listTab},
                                                            onSelectionChanged:
                                                                (s) => setState(
                                                                    () => listTab =
                                                                        s.first),
                                                            showSelectedIcon:
                                                                false,
                                                            style:
                                                                const ButtonStyle(
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              side:
                                                                  WidgetStatePropertyAll(
                                                                BorderSide(
                                                                    color: Color(
                                                                        0xFFE5E7EB)),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      IconButton(
                                                        onPressed: groups
                                                                .isEmpty
                                                            ? null
                                                            : () => setState(() =>
                                                                _multiSelect =
                                                                    true),
                                                        icon: const Icon(
                                                            Icons
                                                                .checklist_rounded,
                                                            size: 20),
                                                        tooltip: '多选删除',
                                                        mouseCursor:
                                                            SystemMouseCursors
                                                                .click,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                          Expanded(
                                            child: listTab == 0
                                                ? GroupListWidget(
                                                    groups: groups,
                                                    selectedIndex:
                                                        selectedGroup,
                                                    onSelect: (i) => setState(
                                                        () =>
                                                            selectedGroup = i),
                                                    multiSelect: _multiSelect,
                                                    selectedGroups:
                                                        _selectedGroups,
                                                    onToggleSelect: (i) =>
                                                        setState(() {
                                                      _selectedGroups
                                                              .contains(i)
                                                          ? _selectedGroups
                                                              .remove(i)
                                                          : _selectedGroups
                                                              .add(i);
                                                    }),
                                                    onDeleteGroup: (i) =>
                                                        _deleteExtras(
                                                            groupIndices: [i]),
                                                  )
                                                : DeletedListWidget(
                                                    items: _deletedImages,
                                                  ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            // 右侧大图预览（约占 60%）
                            Expanded(
                              flex: 6,
                              child: GroupPreviewWidget(
                                group: selectedGroup == null
                                    ? null
                                    : groups[selectedGroup!],
                                onDeleteImage: _deleteImage,
                                onDeleteGroupExtras: () {
                                  if (selectedGroup != null) {
                                    _deleteExtras(
                                        groupIndices: [selectedGroup!]);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                ),
                // 底部状态栏
                _StatusBar(
                  totalImages: result?.images.length ?? 0,
                  groupCount: groups.length,
                  deletedCount: deletedCount,
                  durationMs: result?.durationMs ?? 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空状态/错误提示页（未选文件夹时提供"选择文件夹"主入口）
class _EmptyState extends StatelessWidget {
  final String hint;
  final bool isError;
  final String? folderPath;
  final VoidCallback? onPickFolder;

  const _EmptyState({
    required this.hint,
    this.isError = false,
    this.folderPath,
    this.onPickFolder,
  });

  @override
  Widget build(BuildContext context) {
    if (isError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFDC2626)),
            const SizedBox(height: 16),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.red),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dashboard_customize,
              size: 64, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 20),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF6B7280), height: 1.6),
          ),
          const SizedBox(height: 20),
          // 未选文件夹显示主入口按钮；已选则显示路径 + 更换按钮
          if (folderPath == null)
            FilledButton.icon(
              onPressed: onPickFolder,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('选择文件夹'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                textStyle: const TextStyle(fontSize: 15),
              ),
            )
          else
            Column(
              children: [
                Tooltip(
                  message: folderPath!,
                  child: Text(
                    folderPath!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onPickFolder,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('更换文件夹'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 左侧扫描中提示
class _ScanningHint extends StatelessWidget {
  final ScanProgress? progress;

  const _ScanningHint({required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final ratio = (p == null || p.total == 0) ? null : p.current / p.total;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 16),
          Text(
            p == null ? '正在准备…' : '${p.phaseText} ${p.current}/${p.total}',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2)),
          ),
        ],
      ),
    );
  }
}

/// 底部状态栏
class _StatusBar extends StatelessWidget {
  final int totalImages;
  final int groupCount;
  final int deletedCount;
  final int durationMs;

  const _StatusBar({
    required this.totalImages,
    required this.groupCount,
    required this.deletedCount,
    required this.durationMs,
  });

  Widget _item(String label, String value, {Color? valueColor}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? const Color(0xFF1F2937))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          _item('图片', '$totalImages 张'),
          const SizedBox(width: 20),
          _item('相似组', '$groupCount 组'),
          const SizedBox(width: 20),
          if (deletedCount > 0)
            _item('已删除', '$deletedCount 张',
                valueColor: const Color(0xFFDC2626)),
          const Spacer(),
          if (durationMs > 0) _item('耗时', formatScanTime(durationMs)),
        ],
      ),
    );
  }
}
