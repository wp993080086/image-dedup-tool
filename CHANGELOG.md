# 变更日志

本项目所有重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.0.0] - 2026-10-27

### 新增

- 四种感知哈希算法：pHash / dHash / aHash / mHash，界面单选切换
- 相似阈值 50%–100% 实时筛选，无需重新扫描
- 相似组聚合：基于并查集聚合相似对，组内显示最低相似度
- 大图对比预览：并排展示组内图片（文件名、尺寸、大小）
- 多种删除方式（均移入系统回收站，可还原）：单张删除 / 删除本组多余 / 一键清理 / 多选批量
- 文件夹拖拽：直接拖入窗口即可作为扫描目录
- 子文件夹递归扫描开关
- 哈希缓存：按路径 + 大小 + 修改时间命中，二次扫描显著加速
- 并行扫描：多 isolate 并行解析图片，扫描过程可取消
- 窗口状态记忆：自动保存/恢复窗口位置与大小
- 崩溃日志：全局错误写入 `crash_log.txt`
- BK-tree 哈希分桶优化，将相似对查找从 O(n²) 降至接近 O(n·k)
- 应用 LOGO 图标
- GitHub Actions 自动构建发布（tag 触发）

[Unreleased]: https://github.com/wp993080086/image-dedup-tool/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/wp993080086/image-dedup-tool/releases/tag/v1.0.0
