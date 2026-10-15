import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/app_logger.dart';
import 'package:path/path.dart' as path;

/// 常驻日志的回归测试。
///
/// 存在的理由：这个应用是 GUI 子系统程序，从终端启动读不到 `debugPrint`，于是每次
/// 排查都要临时改代码埋诊断、重新编译、请用户复现。日志常驻之后就不必了 —— 但前提是
/// 它真的**写得进去、转得起来、脱得了敏**，否则等于没有。这里守的就是这几条。
void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('h1-log-test-');
  });

  tearDown(() {
    try {
      sandbox.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 每个用例用独立的 logger 实例，避免单例状态串味。
  Future<AppLogger> fresh(Directory dir) async {
    final logger = AppLogger.forTesting();
    await logger.init(directory: dir);
    return logger;
  }

  group('脱敏', () {
    test('cookie / token / password 的键值对被打掉', () {
      for (final input in [
        'cookie: hanime1_session=abc123',
        'token=abcdef123456',
        'password: hunter2',
        'api_key=sk-1234567890',
      ]) {
        final redacted = AppLogger.redact(input);
        expect(redacted, contains('[已脱敏]'), reason: '没脱敏: $input');
        expect(redacted, isNot(contains('hunter2')));
      }
    });

    test('整段 Cookie 头被打掉（不只第一对键值）', () {
      final redacted = AppLogger.redact('Cookie: a=1; b=2; cf_clearance=xyz');
      expect(redacted, isNot(contains('xyz')));
      expect(redacted, isNot(contains('a=1')));
    });

    test('URL 里的签名参数被打掉（封面 secure 就属于这类）', () {
      final redacted = AppLogger.redact(
        'https://vdownload.hembed.com/image/thumbnail/406505h.jpg?secure=HzeyCoS==,1793414118',
      );
      expect(redacted, isNot(contains('HzeyCoS')));
      expect(redacted, contains('406505h.jpg'), reason: '路径要留着，否则日志失去定位价值');
    });

    test('普通内容不被误伤', () {
      const plain = '[startup] engine+settings: 60ms';
      expect(AppLogger.redact(plain), plain);
    });
  });

  group('写入与分级', () {
    test('info 及以上落盘，debug 不落盘', () async {
      final logger = await fresh(sandbox);
      logger.debug('这条不该进文件');
      logger.info('这条要进');
      logger.warning('警告也要进');
      logger.error('错误也要进');
      await logger.flush();

      final content = await File(path.join(sandbox.path, 'app.log')).readAsString();
      expect(content, contains('这条要进'));
      expect(content, contains('警告也要进'));
      expect(content, contains('错误也要进'));
      expect(content, isNot(contains('这条不该进文件')),
          reason: 'debug 进文件会把真现场刷掉');
    });

    test('日志里带级别标签与时间戳', () async {
      final logger = await fresh(sandbox);
      logger.info('hello', tag: 'startup');
      await logger.flush();
      final content = await File(path.join(sandbox.path, 'app.log')).readAsString();
      expect(content, contains('INFO'));
      expect(content, contains('[startup]'));
      expect(content, matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')));
    });

    test('写入时脱敏（落盘那份本身就该是安全的）', () async {
      final logger = await fresh(sandbox);
      logger.info('token=supersecret123');
      await logger.flush();
      final content = await File(path.join(sandbox.path, 'app.log')).readAsString();
      expect(content, isNot(contains('supersecret123')),
          reason: '导出前才脱敏的话，一次忘记就会泄露');
    });

    test('init 之前记的日志不会丢，init 之后补写', () async {
      final logger = AppLogger.forTesting();
      logger.info('初始化之前的一条');
      await logger.init(directory: sandbox);
      logger.info('初始化之后的一条');
      await logger.flush();
      final content = await File(path.join(sandbox.path, 'app.log')).readAsString();
      expect(content, contains('初始化之前的一条'));
      expect(content, contains('初始化之后的一条'));
    });
  });

  group('轮转', () {
    test('超过上限时转成 app.1.log，当前文件重新开始', () async {
      final logger = await fresh(sandbox);
      // 直接塞到超过 2MB。
      final chunk = 'x' * 4096;
      for (var index = 0; index < 600; index++) {
        logger.info(chunk);
      }
      await logger.flush();

      final files = await logger.files();
      expect(files.length, greaterThan(1), reason: '应当已经轮转出历史文件');
      expect(File(path.join(sandbox.path, 'app.1.log')).existsSync(), isTrue);
    });

    test('保留份数有上限，最旧的被删掉', () async {
      final logger = await fresh(sandbox);
      final chunk = 'y' * 8192;
      // 塞够 7 份以上的量。
      for (var index = 0; index < 2400; index++) {
        logger.info(chunk);
      }
      await logger.flush();

      final files = await logger.files();
      expect(files.length, lessThanOrEqualTo(6),
          reason: '当前 1 份 + 历史 5 份，不能无限增长');
      expect(File(path.join(sandbox.path, 'app.6.log')).existsSync(), isFalse);
    });
  });

  group('导出与清理', () {
    test('导出的是 zip，且含全部日志文件', () async {
      final logger = await fresh(sandbox);
      logger.info('要导出的内容');
      await logger.flush();

      final bytes = await logger.exportZip();
      expect(bytes, isNotEmpty);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.map((file) => file.name), contains('app.log'));
      final decoded = utf8.decode(archive.files.first.content as List<int>);
      expect(decoded, contains('要导出的内容'));
    });

    test('清空之后没有日志文件', () async {
      final logger = await fresh(sandbox);
      logger.info('清空前');
      await logger.flush();
      expect((await logger.files()).isNotEmpty, isTrue);

      await logger.clear();
      expect((await logger.files()).isEmpty, isTrue);
      expect(await logger.size(), 0);
    });

    test('size 反映实际占用', () async {
      final logger = await fresh(sandbox);
      logger.info('a' * 1000);
      await logger.flush();
      expect(await logger.size(), greaterThan(1000));
    });
  });
}
