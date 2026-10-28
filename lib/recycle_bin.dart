import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// ===== Win32 常量 =====
const int _foDelete = 3;
const int _fofAllowUndo = 0x40;
const int _fofNoConfirmation = 0x10;
const int _fofNoErrorUi = 0x400;
const int _fofSilent = 0x4;

/// SHFILEOPSTRUCTW 结构体（dart:ffi 按 C 规则自动对齐）
final class _ShFileOpStruct extends Struct {
  external Pointer<Void> hwnd;

  @Uint32()
  external int wFunc;

  external Pointer<Utf16> pFrom;

  external Pointer<Utf16> pTo;

  @Uint16()
  external int fFlags;

  @Int32()
  external int fAnyOperationsAborted;

  external Pointer<Void> hNameMappings;

  external Pointer<Utf16> lpszProgressTitle;
}

typedef _SHFileOperationWNative = Int32 Function(Pointer<_ShFileOpStruct>);
typedef _SHFileOperationWDart = int Function(Pointer<_ShFileOpStruct>);

/// 删除文件列表：Windows 移入系统回收站（可还原），其他平台直接删除。
///
/// 返回删除失败的路径列表。批量操作在后台 isolate 中执行，避免阻塞 UI。
Future<List<String>> deleteFilesToRecycleBin(List<String> paths) {
  if (paths.isEmpty) return Future.value([]);
  return Isolate.run(() => _deleteSync(paths));
}

/// 同步删除实现（后台 isolate 中执行）
List<String> _deleteSync(List<String> paths) {
  if (!Platform.isWindows) return _deleteDirectly(paths);
  return _moveToRecycleBin(paths);
}

/// 非 Windows 平台：直接删除
List<String> _deleteDirectly(List<String> paths) {
  final failed = <String>[];
  for (final path in paths) {
    try {
      File(path).deleteSync();
    } catch (_) {
      failed.add(path);
    }
  }
  return failed;
}

/// Windows：调用 SHFileOperation（FOF_ALLOWUNDO）把文件移入回收站
List<String> _moveToRecycleBin(List<String> paths) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final shFileOperation =
      shell32.lookupFunction<_SHFileOperationWNative, _SHFileOperationWDart>(
          'SHFileOperationW');

  // 多路径格式："path1\0path2\0\0"（双 null 结尾，toNativeUtf16 会补最后一个）
  final from = '${paths.join('\x00')}\x00'.toNativeUtf16();
  final op = malloc<_ShFileOpStruct>();
  try {
    op.ref.hwnd = nullptr;
    op.ref.wFunc = _foDelete;
    op.ref.pFrom = from;
    op.ref.pTo = nullptr;
    op.ref.fFlags =
        _fofAllowUndo | _fofNoConfirmation | _fofNoErrorUi | _fofSilent;
    op.ref.fAnyOperationsAborted = 0;
    op.ref.hNameMappings = nullptr;
    op.ref.lpszProgressTitle = nullptr;
    final rc = shFileOperation(op);
    return rc == 0 ? [] : paths;
  } catch (_) {
    return paths;
  } finally {
    malloc.free(from);
    malloc.free(op);
  }
}
