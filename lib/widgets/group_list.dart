import 'package:image_dedup/models.dart';
import 'package:image_dedup/utils.dart';
import 'package:flutter/material.dart';

/// 左侧"已删除"页签：本次会话删除的图片网格
class DeletedListWidget extends StatelessWidget {
  final List<ImageData> items;

  const DeletedListWidget({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('本次尚未删除图片',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 还原提示条
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已移入系统回收站，可打开回收站还原',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final img = items[i];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: double.infinity,
                          child: Image.memory(
                            img.thumbnail,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.broken_image,
                                    size: 28, color: Colors.grey[300])),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Tooltip(
                      message: img.path,
                      child: Text(
                        img.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${img.width}×${img.height} · ${formatSize(img.size)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 左侧相似组列表
class GroupListWidget extends StatelessWidget {
  final List<SimilarGroup> groups;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  /// 多选模式
  final bool multiSelect;
  final Set<int> selectedGroups;
  final ValueChanged<int> onToggleSelect;

  /// 单组清理（删除本组多余图片，保留 1 张）
  final ValueChanged<int> onDeleteGroup;

  const GroupListWidget({
    super.key,
    required this.groups,
    required this.selectedIndex,
    required this.onSelect,
    required this.multiSelect,
    required this.selectedGroups,
    required this.onToggleSelect,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_search, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('未发现相似图片',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
            Text('可尝试降低相似阈值',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _GroupCard(
          group: groups[index],
          order: index + 1,
          selected: !multiSelect && selectedIndex == index,
          checked: multiSelect && selectedGroups.contains(index),
          multiSelect: multiSelect,
          onTap: () => multiSelect ? onToggleSelect(index) : onSelect(index),
          onDeleteGroup: () => onDeleteGroup(index),
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  final SimilarGroup group;
  final int order;
  final bool selected;
  final bool checked;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onDeleteGroup;

  const _GroupCard({
    required this.group,
    required this.order,
    required this.selected,
    required this.checked,
    required this.multiSelect,
    required this.onTap,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    final simColor = similarityColor(group.similarity);
    // 最多展示 4 张缩略图
    final thumbs = group.images.take(4).toList();
    final extra = group.images.length - thumbs.length;

    return Material(
      color: checked
          ? const Color(0xFFF0F5FF)
          : selected
              ? const Color(0xFFF0F5FF)
              : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (selected || checked)
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFE5E7EB),
              width: (selected || checked) ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '组 $order',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: simColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${group.similarity.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: simColor),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${group.images.length} 张',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const Spacer(),
                  // 多选模式显示勾选框，普通模式显示单组清理按钮
                  if (multiSelect)
                    SizedBox(
                      height: 22,
                      width: 22,
                      child: Checkbox(
                        value: checked,
                        onChanged: (_) => onTap(),
                        mouseCursor: SystemMouseCursors.click,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                  else
                    Tooltip(
                      message: '删除本组多余图片（保留 1 张）',
                      child: InkWell(
                        onTap: onDeleteGroup,
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(Icons.delete_sweep_outlined,
                              size: 18, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < thumbs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        thumbs[i].thumbnail,
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ],
                  if (extra > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+$extra',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
