import 'dart:io';

import 'package:image_dedup/models.dart';
import 'package:image_dedup/utils.dart';
import 'package:flutter/material.dart';

/// 右侧面板：选中相似组后显示组内大图对比
class GroupPreviewWidget extends StatelessWidget {
  final SimilarGroup? group;

  /// 删除回调
  final void Function(ImageData image) onDeleteImage;
  final VoidCallback onDeleteGroupExtras;

  const GroupPreviewWidget({
    super.key,
    required this.group,
    required this.onDeleteImage,
    required this.onDeleteGroupExtras,
  });

  @override
  Widget build(BuildContext context) {
    final g = group;
    if (g == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('点击左侧相似组查看大图对比',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      );
    }

    final simColor = similarityColor(g.similarity);
    return Container(
      color: const Color(0xFFEFF1F4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组信息头 + 组内清理按钮
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('组内对比',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: simColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '最低相似度 ${g.similarity.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: simColor),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${g.images.length} 张图片',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const Spacer(),
                if (g.images.length > 1)
                  TextButton.icon(
                    onPressed: onDeleteGroupExtras,
                    icon: const Icon(Icons.cleaning_services, size: 16),
                    label:
                        const Text('删除本组多余图片', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey[200]),
          // 图片自适应网格
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = g.images.length;
                final width = constraints.maxWidth - 32;
                // 根据可用宽度决定列数（每列至少约 300px），至少 1 列
                final columns =
                    width < 320 ? 1 : (width / 320).floor().clamp(1, count);
                final gap = 12.0;
                final cardWidth = (width - gap * (columns - 1)) / columns;
                final cardHeight = cardWidth * 0.75 + 56;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final img in g.images)
                        _ImageCard(
                          data: img,
                          width: cardWidth,
                          height: cardHeight,
                          onDelete: () => onDeleteImage(img),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 组内单张图片卡片（大图 + 信息 + 删除按钮）
class _ImageCard extends StatelessWidget {
  final ImageData data;
  final double width;
  final double height;
  final VoidCallback onDelete;

  const _ImageCard({
    required this.data,
    required this.width,
    required this.height,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 大图区域（含悬浮删除按钮）
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(data.path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.broken_image,
                            size: 48, color: Colors.grey[300]),
                      ),
                    ),
                  ),
                ),
                // 右上角删除按钮
                Positioned(
                  top: 4,
                  right: 4,
                  child: Tooltip(
                    message: '删除这张图片',
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        onTap: onDelete,
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(Icons.delete_outline,
                              size: 18, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey[200]),
          // 图片信息
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: data.path,
                  child: Text(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937)),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.width}×${data.height} · ${formatSize(data.size)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
