import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'platform_paths.dart';

/// 应用日志。
///
/// 解决的是一个反复出现的具体痛点：应用是 `IMAGE_SUBSYSTEM_WINDOWS_GUI` 的 Windows 程序
/// （PE Subsystem = 2），从 PowerShell/CMD 启动时**不会 attach 到父控制台**，`debugPrint`
/// 一个字节都读不到。于是每次排查问题都要临时往代码里埋一条诊断、重新编译、让用户复现，
/// 拿到结果再把诊断删掉 —— 这个过程本身既慢又容易把临时代码留在仓库里。
///
/// 所以这里做成**常驻**的：日志一直写，出问题时直接从设置页导出，不需要改代码。
///
/// 设计上借了 AniBaka（`lib/utils/app_logger.dart`）的做法，几处关键取舍：
///
/// * **自己实现，不引第三方日志库**。需要的只是「分级 + 落盘 + 轮转 + 脱敏 + 导出」，
///   引一个包进来还要为它维护配置与版本，收益不划算。
/// * **只有 info 及以上才落盘**。`debug` 仍然走 `debugPrint`（开发时在控制台看），
///   但不进文件 —— 否则高频的调试输出会把日志刷满，真出事时关键几行早被轮转掉了。
/// * **按大小轮转、保留有限份数**。日志是诊断材料，不是数据，不能无限长。
/// * **写盘失败静默**。日志本身绝不能拖垮应用；磁盘满、目录只读时应当照常运行。
class AppLogger {
  AppLogger._();

  /// 测试用的独立实例。
  ///
  /// [instance] 是单例（`debugPrint` 的接管只能做一次），测试里需要互不干扰的
  /// 实例，所以留这个口子。生产代码只用 [instance]。
  @visibleForTesting
  factory AppLogger.forTesting() => AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// 单个日志文件的大小上限。超过就轮转。
  ///
  /// 2MB 是权衡后的值：一次完整启动 + 一次登录尝试大约产生几十 KB，2MB 足够覆盖
  /// 好几天的正常使用；再大的话导出时用户要传的文件就太重了。
  static const int _maxLogFileBytes = 2 * 1024 * 1024;

  /// 保留的历史文件份数（不含当前那份）。轮转时最旧的被删掉。
  static const int _maxLogFiles = 5;

  static const String _activeFileName = 'app.log';

  /// 日志目录：`<应用数据目录>/logs`。
  ///
  /// 必须走 [appStorageDirectory]，不能走 `getApplicationSupportDirectory` —— 后者在
  /// Windows 上按 exe 的 VERSIONINFO 拼路径，会落到历史遗留目录里（见 platform_paths.dart）。
  Directory? _directory;
  File? _file;
  bool _initialized = false;

  /// 写盘串行化。日志来自任意线程/任意异步点，并发写同一个文件会互相踩。
  Future<void> _writes = Future<void>.value();

  /// 当前文件已写入的字节数，用于判断是否需要轮转（免得每次都去 stat 文件）。
  int _written = 0;

  Directory? get directory => _directory;
  File? get file => _file;
  bool get initialized => _initialized;

  /// 初始化：建目录、接上未捕获异常、写一条启动分隔。
  ///
  /// 幂等。失败不抛（日志目录建不出来不该阻止应用启动）。
  Future<void> init({Directory? directory}) async {
    if (_initialized) return;
    try {
      final target = directory ?? Directory(path.join((await appStorageDirectory()).path, 'logs'));
      await target.create(recursive: true);
      _directory = target;
      _file = File(path.join(target.path, _activeFileName));
      _written = await _file!.exists() ? await _file!.length() : 0;
      _initialized = true;
      _captureDebugPrint();
      // 初始化之前攒下的那几行现在补写。
      //
      // 必须在 `_initialized = true` **之后**做：`_append` 只在已初始化时才真正落盘，
      // 早一步调用会被当成「还没 ready」再攒回去，日志就永远丢在那批 pending 里。
      final backlog = List<String>.from(_pending);
      _pending.clear();
      for (final entry in backlog) {
        _append(LogLevel.info, entry, 'early');
      }
    } catch (_) {
      _initialized = false;
    }
  }

  /// 把 Flutter 框架内所有 `debugPrint` 也接进日志。
  ///
  /// 代码里那 35 处 `debugPrint` 有不少是排查时真正要看的（启动耗时、播放器状态、
  /// WebView 环境创建结果），不接进来等于白留。
  ///
  /// **必须直接写文件，不能回头调 [info]**：`debug()` 本身就是走 `debugPrint` 的，
  /// 一旦接成 `debugPrint → info → _append`，`debug` 级别就会绕过「只走控制台」
  /// 的约定被写进文件，而且 `_append` 里的日志再触发 `debugPrint` 时还会自我递归。
  /// 用 [_capturingDebugPrint] 做守卫，彻底断掉这条回路。
  void _captureDebugPrint() {
    if (_capturingDebugPrint) return;
    _capturingDebugPrint = true;
    // 先把原始实现固化下来，再替换 —— 顺序反了的话 [_originalDebugPrint] 首次求值时
    // 拿到的就是「替换后的自己」，`debug()` 会变成自我递归、并把 debug 行写进文件。
    // 实测踩过：app.log 里出现 `DEBUG[debugPrint] [DEBUG] ...`。
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint(message, wrapWidth: wrapWidth);
      if (message == null || !_initialized) return;
      final line = '${DateTime.now().toIso8601String()} DEBUG[debugPrint] '
          '${redact(message)}\n';
      _writes = _writes.then((_) => _writeLine(line)).catchError((Object _) {});
    };
  }

  /// `debugPrint` 是否已经被接过（防止重复包装导致重复落盘）。
  bool _capturingDebugPrint = false;

  void debug(String message, {String? tag}) => _emit(LogLevel.debug, message, tag);
  void info(String message, {String? tag}) => _emit(LogLevel.info, message, tag);
  void warning(String message, {String? tag}) => _emit(LogLevel.warning, message, tag);
  void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' | $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    _emit(LogLevel.error, buffer.toString(), tag);
  }

  /// 记一条外部进来的完整异常（`FlutterError.onError` / `runZonedGuarded` 的入口）。
  void recordException(Object error, StackTrace? stackTrace, {String? tag}) =>
      this.error('未捕获异常', tag: tag, error: error, stackTrace: stackTrace);

  /// 等待所有排队中的写入落盘。
  ///
  /// 生产代码不需要它（日志是 fire-and-forget）；测试要断言文件内容时必须等，
  /// 否则读到的是写之前的快照。
  @visibleForTesting
  Future<void> flush() => _writes;

  void _emit(LogLevel level, String message, String? tag) {
    // debug 不落盘，只给控制台（见类注释）。
    //
    // **必须用 [_originalDebugPrint] 而不是 `debugPrint`**：后者在 init 时已被接管，
    // 接管后的实现会把内容写进文件 —— 直接调它等于让 debug 级别绕过「不落盘」的约定，
    // 而且接管实现内部再记日志时会自我递归。实测踩过：debug 的行出现在 app.log 里。
    if (level == LogLevel.debug) {
      _originalDebugPrint('[${level.label}]${tag == null ? '' : '[$tag]'} $message');
      return;
    }
    if (!_initialized) {
      // 初始化之前发生的日志不能丢：先攒着，初始化后补写。
      _pending.add('${level.label}${tag == null ? '' : '[$tag]'} $message');
      return;
    }
    _append(level, message, tag);
  }

  /// 初始化之前产生的日志行，等 [init] 完成后一次性补写。
  final _pending = <String>[];

  /// 接管 `debugPrint` 之前的那份实现。
  ///
  /// 接管之后 `debugPrint` 会写文件，所以凡是「只该进控制台」的输出都必须走这个原始版本，
  /// 否则就绕过了分级约定（见 [_emit]）。
  ///
  /// 在 [_captureDebugPrint] 里**先赋值再替换**，不是 `late final` 懒求值 —— 懒求值会
  /// 在替换之后才执行，拿到的就是替换后的自己。
  void Function(String? message, {int? wrapWidth}) _originalDebugPrint = debugPrint;

  void _append(LogLevel level, String message, String? tag) {
    final redacted = redact('${level.label}${tag == null ? '' : '[$tag]'} $message');
    final line = '${DateTime.now().toIso8601String()} $redacted\n';
    _writes = _writes.then((_) => _writeLine(line)).catchError((Object _) {});
  }

  Future<void> _writeLine(String line) async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(line, mode: FileMode.append, flush: false);
      _written += line.length;
      if (_written >= _maxLogFileBytes) await _rotate();
    } catch (_) {
      // 日志写不进去不该影响应用。
    }
  }

  /// 把当前文件改名成 `app.1.log`，历史文件依次后移，最旧的删掉。
  Future<void> _rotate() async {
    final directory = _directory;
    final file = _file;
    if (directory == null || file == null) return;
    try {
      final oldest = File(path.join(directory.path, 'app.$_maxLogFiles.log'));
      if (await oldest.exists()) await oldest.delete();
      for (var index = _maxLogFiles - 1; index >= 1; index--) {
        final from = File(path.join(directory.path, 'app.$index.log'));
        if (!await from.exists()) continue;
        await from.rename(path.join(directory.path, 'app.${index + 1}.log'));
      }
      if (await file.exists()) await file.rename(path.join(directory.path, 'app.1.log'));
      await file.create(recursive: true);
      _written = 0;
    } catch (_) {
      // 轮转失败就继续往原文件写，总比丢日志强。
    }
  }

  /// 现有日志文件（当前 + 历史），当前那份排最前。
  Future<List<File>> files() async {
    final directory = _directory;
    if (directory == null || !await directory.exists()) return const [];
    final result = <File>[];
    final active = File(path.join(directory.path, _activeFileName));
    if (await active.exists()) result.add(active);
    for (var index = 1; index <= _maxLogFiles; index++) {
      final file = File(path.join(directory.path, 'app.$index.log'));
      if (await file.exists()) result.add(file);
    }
    return result;
  }

  /// 全部日志占用的字节数（设置页显示用）。
  Future<int> size() async {
    var total = 0;
    for (final file in await files()) {
      try {
        total += await file.length();
      } catch (_) {}
    }
    return total;
  }

  /// 清空所有日志文件。
  ///
  /// 删完**不重建空文件**：`files()` 会把存在的文件都列出来，重建的话「清空」之后
  /// 设置页仍显示一个 0 字节的文件，看起来像没清干净。下一次 `_writeLine` 自己会
  /// 按 append 语义创建它。
  Future<void> clear() async {
    // 先排空在途写入，否则排队中的那几行会在删除之后又被写回来。
    try {
      await _writes;
    } catch (_) {}
    for (final file in await files()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    _written = 0;
  }

  /// 把脱敏后的全部日志打包成 ZIP，返回字节。
  ///
  /// 打成 ZIP 而不是直接给 `.log`：多份轮转文件要一起交给开发者，单文件没法带全。
  Future<List<int>> exportZip() async {
    final archive = Archive();
    for (final file in await files()) {
      try {
        final content = await file.readAsString();
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(path.basename(file.path), bytes.length, bytes));
      } catch (_) {}
    }
    return ZipEncoder().encode(archive);
  }

  /// 脱敏：把日志里可能出现的凭据换成占位符。
  ///
  /// 日志会被导出、贴进 issue、发给别人看，所以**在写入时**就脱敏，而不是导出时才做 ——
  /// 落盘的那份本身就应当是安全的，否则一次忘记脱敏的导出就会泄露。
  ///
  /// 覆盖三类：`key=value` 形式的敏感键、`Authorization` 头、以及长串的
  /// token/cookie 值（凭据往往是一长串无空格字符）。
  @visibleForTesting
  static String redact(String input) {
    var output = input;
    // 1) cookie / token / password 之类的键值对。
    output = output.replaceAllMapped(
      RegExp(
        r'((?:cookie|set-cookie|authorization|token|password|passwd|pwd|secret|api[-_]?key|session|csrf)[^:=\s]*\s*[:=]\s*)([^\s;,"]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[已脱敏]',
    );
    // 2) 整段 Cookie 头（`k=v; k=v` 形式，前面的规则只能盖住第一对）。
    output = output.replaceAllMapped(
      RegExp(r'((?:cookie|set-cookie)\s*:\s*)(.+)', caseSensitive: false),
      (match) => '${match.group(1)}[已脱敏]',
    );
    // 3) 查询串里的签名/令牌参数（图片 URL 的 secure 就属于这类）。
    output = output.replaceAllMapped(
      RegExp(r'([?&](?:secure|token|sign|signature|expires|authkey)=)([^&\s]+)', caseSensitive: false),
      (match) => '${match.group(1)}[已脱敏]',
    );
    return output;
  }
}

/// 日志级别。只有 [info] 及以上会落盘。
enum LogLevel {
  debug('DEBUG'),
  info('INFO'),
  warning('WARN'),
  error('ERROR');

  const LogLevel(this.label);
  final String label;
}

/// 初始化日志并接上全局错误处理。
///
/// 必须在任何业务代码之前调用：早期启动阶段的失败（设置读不出来、WebView2 环境建不起来）
/// 恰恰是最需要日志的时刻，晚一步就什么都捕捉不到。
Future<void> initAppLogger() async {
  final logger = AppLogger.instance;
  await logger.init();
  logger.info('=== 应用启动 v$appLoggerVersionLabel pid=$pid ===', tag: 'startup');

  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previousFlutterError?.call(details);
    logger.recordException(details.exception, details.stack, tag: 'flutter');
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.recordException(error, stack, tag: 'platform');
    return true;
  };
}

/// 版本号标签。
///
/// 用注入的方式而不是在这里读 `package_info_plus`：那个调用是异步的，而启动日志
/// 要尽早落盘。`main` 里读完版本后通过这个变量交给日志，拿不到就显示占位符 ——
/// 日志本身不该因为读版本失败而中断。
String appLoggerVersionLabel = 'unknown';
