import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_identity.dart';
import '../../core/platform_service.dart';
import '../local/json_store.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.htmlUrl,
    required this.body,
    required this.createdAt,
    required this.downloadUrl,
    required this.prerelease,
  });

  final String tagName;
  final String htmlUrl;
  final String body;
  final String createdAt;
  final String downloadUrl;
  final bool prerelease;

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'htmlUrl': htmlUrl,
        'body': body,
        'createdAt': createdAt,
        'downloadUrl': downloadUrl,
        'prerelease': prerelease,
      };

  static UpdateInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final tagName = '${json['tagName'] ?? ''}'.trim();
    if (tagName.isEmpty) return null;
    return UpdateInfo(
      tagName: tagName,
      htmlUrl: '${json['htmlUrl'] ?? ''}',
      body: '${json['body'] ?? ''}',
      createdAt: '${json['createdAt'] ?? ''}',
      downloadUrl: '${json['downloadUrl'] ?? ''}',
      prerelease: json['prerelease'] == true,
    );
  }
}

class UpdateChecker {
  UpdateChecker(this._dio, {ReleaseCache? cache}) : _cache = cache;

  final Dio _dio;
  final ReleaseCache? _cache;

  /// 上一次取发布信息是否失败（网络不可用或额度用尽）。
  ///
  /// 失败时 [latestRelease]/[check] 会回退到缓存；调用方可以用它区分
  /// 「确实没有新版本」和「根本没查到」，避免给出误导提示。
  bool get lastCallFailed => _lastCallFailed;
  var _lastCallFailed = false;

  Future<UpdateInfo?> check({String? currentVersion}) async {
    try {
      final release = await latestRelease();
      if (release == null) return null;
      final installedVersion = currentVersion ?? (await PackageInfo.fromPlatform()).version;
      if (release.tagName.isEmpty || !_newer(release.tagName, installedVersion)) return null;
      return release;
    } catch (_) {
      return null;
    }
  }

  /// 取最新一次发布，不比较版本（用于「更新日志」；已是最新版本时也要看得到）。
  ///
  /// 带本地缓存与 `If-None-Match` 条件请求：内容没变时服务端返回 304，而 **304 不
  /// 计入 GitHub 的速率额度**，所以反复检查几乎不消耗额度；网络不可用或额度用尽
  /// （未认证只有每 IP 每小时 60 次）时回退到上一次缓存的结果。
  Future<UpdateInfo?> latestRelease() async {
    final cached = await _cache?.read();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            if (cached?.etag case final etag?) 'If-None-Match': etag,
          },
          // 304 表示缓存仍有效，按成功处理（Dio 默认会把 3xx 当异常抛）。
          validateStatus: (status) => status != null && (status == 304 || (status >= 200 && status < 300)),
        ),
      );
      if (response.statusCode == 304) {
        _lastCallFailed = false;
        return cached?.info;
      }
      final data = response.data;
      if (data == null) return cached?.info;
      final tag = '${data['tag_name'] ?? ''}'.trim();
      if (tag.isEmpty) return cached?.info;
      final assets = (data['assets'] as List? ?? const []).whereType<Map>().cast<Map>();
      final asset = await _selectAsset(assets);
      final downloadUrl = Platform.isMacOS
          ? '$repoUrl/releases/latest'
          : '${asset?['browser_download_url'] ?? ''}'.trim();
      final htmlUrl = '${data['html_url'] ?? ''}'.trim();
      final info = UpdateInfo(
        tagName: tag,
        htmlUrl: htmlUrl,
        body: '${data['body'] ?? ''}',
        createdAt: '${data['created_at'] ?? ''}',
        downloadUrl: downloadUrl.isNotEmpty || Platform.isAndroid ? downloadUrl : htmlUrl,
        prerelease: data['prerelease'] == true,
      );
      await _writeCache(info, response.headers.value('etag'));
      _lastCallFailed = false;
      return info;
    } catch (_) {
      // 额度用尽/断网：先用不计额度的 Atom 源（信息最新），再退到上次缓存。
      final fallback = await _latestFromFeed();
      _lastCallFailed = fallback == null;
      return fallback ?? cached?.info;
    }
  }

  /// 无额度兜底：从 `releases.atom` 取最新一次发布。
  ///
  /// 这个源由 github.com 直接提供，不占用 REST API 每 IP 每小时 60 次的额度，
  /// 所以额度用尽时仍能拿到版本号与更新说明（正文是 HTML，转成纯文本显示）。
  /// 免额度路径拿不到资产列表，Windows 下载地址按安装包名约定拼出。
  Future<UpdateInfo?> _latestFromFeed() async {
    if (!Platform.isWindows) return null;
    try {
      final response = await _dio.get<String>(
        '$repoUrl/releases.atom',
        options: Options(responseType: ResponseType.plain, headers: {'Accept': 'application/atom+xml, text/xml, */*'}),
      );
      final entry = RegExp(r'<entry>(.*?)</entry>', dotAll: true).firstMatch(response.data ?? '')?.group(1);
      if (entry == null) return null;
      final tag = RegExp(r'/releases/tag/([^"<\s]+)').firstMatch(entry)?.group(1)?.trim() ?? '';
      if (tag.isEmpty) return null;
      final content = RegExp(r'<content[^>]*>(.*?)</content>', dotAll: true).firstMatch(entry)?.group(1) ?? '';
      return UpdateInfo(
        tagName: tag,
        htmlUrl: RegExp(r'<link rel="alternate"[^>]*href="([^"]+)"').firstMatch(entry)?.group(1) ?? '$repoUrl/releases/tag/$tag',
        body: _htmlToText(_unescapeXml(content)),
        createdAt: RegExp(r'<updated>(.*?)</updated>').firstMatch(entry)?.group(1) ?? '',
        downloadUrl: '$repoUrl/releases/latest/download/$installerBaseName.exe',
        prerelease: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// 缓存落盘失败（磁盘/权限等）不影响本次结果。
  Future<void> _writeCache(UpdateInfo info, String? etag) async {
    try {
      await _cache?.write(info, etag);
    } catch (_) {}
  }

  Future<Map?> _selectAsset(Iterable<Map> assets) async {
    if (Platform.isAndroid) {
      final abi = await PlatformService.androidUpdateAbi();
      final variant = switch (abi) {
        'arm64-v8a' => 'arm64',
        'armeabi-v7a' => 'arm32',
        'x86_64' => 'x64',
        _ => null,
      };
      return variant == null
          ? null
          : assets
              .where((asset) => '${asset['name'] ?? ''}'.toLowerCase() == 'android.$variant.apk')
              .firstOrNull;
    }
    return switch (Platform.operatingSystem) {
      'linux' => _firstMatching(assets, const ['.tar.gz', '.tar.xz', '.deb']),
      'windows' => _windowsAsset(assets),
      'ios' => _firstMatching(assets, const ['.ipa']),
      'macos' => _firstMatching(assets, const ['.dmg']),
      _ => null,
    };
  }

  Map? _windowsAsset(Iterable<Map> assets) {
    final exes = assets
        .where((asset) => '${asset['name'] ?? ''}'.toLowerCase().endsWith('.exe'))
        .toList(growable: false);
    if (exes.isEmpty) return null;
    return exes.firstWhere(
      (asset) {
        final name = '${asset['name'] ?? ''}'.toLowerCase();
        return name.contains('setup') || name.contains('installer');
      },
      orElse: () => exes.first,
    );
  }

  Map? _firstMatching(Iterable<Map> assets, List<String> suffixes) {
    for (final suffix in suffixes) {
      final match = assets
          .where((asset) => '${asset['name'] ?? ''}'.toLowerCase().endsWith(suffix))
          .firstOrNull;
      if (match != null) return match;
    }
    return null;
  }

  bool _newer(String remote, String local) {
    final remoteParts = _parts(remote);
    final localParts = _parts(local);
    for (var index = 0; index < 3; index++) {
      if (remoteParts[index] != localParts[index]) {
        return remoteParts[index] > localParts[index];
      }
    }
    return false;
  }

  List<int> _parts(String value) {
    final parts = value
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('-')
        .first
        .split('+')
        .first
        .split('.');
    return List.generate(
      3,
      (index) => index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
    );
  }
}

/// 还原 Atom 正文里被转义的 HTML 实体。
String _unescapeXml(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 把发布说明的 HTML 转成纯文本（复用已有的 html 包，不引新依赖）。
String _htmlToText(String html) => (html_parser.parse(html).body?.text ?? '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join('\n');

/// 最近一次成功获取的发布信息及它的 ETag。
class CachedRelease {
  const CachedRelease({required this.info, this.etag});

  final UpdateInfo info;
  final String? etag;
}

/// 发布信息缓存（`release_cache.json`）。
class ReleaseCache {
  ReleaseCache([JsonStore? store]) : _store = store ?? JsonStore();

  final JsonStore _store;
  static const _fileName = 'release_cache.json';

  Future<CachedRelease?> read() async {
    final json = await _store.read(_fileName);
    final info = UpdateInfo.fromJson(json['release']);
    if (info == null) return null;
    final etag = '${json['etag'] ?? ''}';
    return CachedRelease(info: info, etag: etag.isEmpty ? null : etag);
  }

  Future<void> write(UpdateInfo info, String? etag) => _store.write(_fileName, {'etag': etag, 'release': info.toJson()});
}

/// 全局共享的更新检查器（带缓存），避免每个调用点各建一个实例。
final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker(Dio(), cache: ReleaseCache()));
