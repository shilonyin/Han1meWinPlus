import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../remote/jav/jav_site.dart';
import 'json_store.dart';

/// 站点选择弹层里的一个分组。
///
/// [name] 为空表示「用内置默认名」—— 默认组的名字于是跟随界面语言（切语言时跟着变），
/// 只有用户改过名才存实际文本。
class SiteGroup {
  const SiteGroup({required this.id, this.name = '', required this.hosts});

  final String id;
  final String name;
  final List<String> hosts;

  SiteGroup copyWith({String? name, List<String>? hosts}) => SiteGroup(id: id, name: name ?? this.name, hosts: hosts ?? this.hosts);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'hosts': hosts};

  static SiteGroup? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return SiteGroup(id: id, name: value['name']?.toString() ?? '', hosts: (value['hosts'] as List? ?? const []).map((host) => host.toString()).toList(growable: false));
  }
}

/// 内置分组 id（Hanime1 系 / AV 视频源）。用户自建的组用 [newSiteGroupId] 生成。
const defaultSiteGroupId = 'default';
const javSiteGroupId = 'jav';

/// 内置默认站点（`comicMode` 下只有第一个）。
const builtInSiteHosts = ['https://hanime1.com', 'https://hanimeone.me', 'https://hanime1.me'];

/// 用户自建分组的 id：'g' + 微秒时间戳（本地单机够用，不必引入 uuid 依赖）。
String newSiteGroupId() => 'g${DateTime.now().microsecondsSinceEpoch}';

/// 内置默认分组。用户没有自定义过、或者把所有分组都删光时会回到这里。
List<SiteGroup> defaultSiteGroups({required bool comicMode}) => [
      SiteGroup(id: defaultSiteGroupId, hosts: comicMode ? const ['https://hanimeone.me'] : builtInSiteHosts),
      if (!comicMode) SiteGroup(id: javSiteGroupId, hosts: [for (final site in javSites) site.baseUrl]),
    ];

/// 站点分组的持久化 + **自动归类**。
///
/// 站点清单是随版本变化的（以后可能新增 AV 源、或者增减内置默认站点），所以存下来的配置
/// 只是「用户的意图」，真正要用的时候必须与当前清单对齐：
/// 新出现的站点自动补进它默认该在的组、已经不存在的站点丢掉、同一个站点被多个组认领时
/// 只留第一个。这样用户不必因为一次升级就手动维护分组。
///
/// 注意：**删除分组不会丢站点** —— 界面层会把被删组里的站点并入第一个组，所以这里不会
/// 出现「有站点没被任何组认领」的情况，也就不会把用户删掉的组又自动加回来。
class SiteGroupStore {
  SiteGroupStore(this._store);

  final JsonStore _store;
  static const _fileName = 'site_groups.json';

  Future<List<SiteGroup>> read({required bool comicMode}) async {
    final stored = [for (final value in (await _store.read(_fileName))['groups'] as List? ?? const []) SiteGroup.fromJson(value)].whereType<SiteGroup>().toList(growable: false);
    return align(stored, comicMode: comicMode);
  }

  Future<void> write(List<SiteGroup> groups) async => _store.write(_fileName, {'groups': [for (final group in groups) group.toJson()]});

  /// 把配置与当前站点清单对齐（默认情况下的自动归类）。
  static List<SiteGroup> align(List<SiteGroup> stored, {required bool comicMode}) {
    final fallback = defaultSiteGroups(comicMode: comicMode);
    final known = {for (final group in fallback) ...group.hosts};
    if (stored.isEmpty) return fallback;
    final claimed = <String>{};
    final aligned = <SiteGroup>[];
    for (final group in stored) {
      // 已经不存在的地址、以及被前一个组认领过的地址都去掉。
      final hosts = [for (final host in group.hosts) if (known.contains(host) && claimed.add(host)) host];
      aligned.add(group.copyWith(hosts: hosts));
    }
    for (final host in known) {
      if (claimed.contains(host)) continue;
      final target = fallback.firstWhere((group) => group.hosts.contains(host), orElse: () => fallback.first);
      final index = aligned.indexWhere((group) => group.id == target.id);
      if (index >= 0) {
        aligned[index] = aligned[index].copyWith(hosts: [...aligned[index].hosts, host]);
      } else {
        aligned.add(SiteGroup(id: target.id, hosts: [host]));
      }
      claimed.add(host);
    }
    return aligned;
  }
}

/// 分组配置的存储。分组的**展示**（默认名跟随语言、与站点清单对齐的入口）由 UI 层负责，
/// 所以这里只依赖 [JsonStore]。
final siteGroupStoreProvider = Provider((ref) => SiteGroupStore(JsonStore()));
