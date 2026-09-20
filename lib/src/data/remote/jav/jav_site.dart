/// AV 视频源（第三方 JAV 站点）注册表。
///
/// 这些站点与 hanime1 是两套完全不同的页面结构，解析放在同目录的 `JavApi` 里，
/// 由 `Han1meRepository` 按当前站点地址分发过去；账号、清单、评论这些只属于
/// hanime1 的能力在 AV 源下会降级（见 `Han1meRepository` 里的判断）。
///
/// 新增一个源 = 在这里登记 + 在 `JavApi` 里补上对应 [JavSiteKind] 的解析分支。
enum JavSiteKind {
  /// missav.ai：Alpine.js + Tailwind，卡片与详情都是服务端渲染，
  /// 但播放地址藏在 Dean Edwards packer 打包的内联脚本里。
  missav,

  /// jable.tv：KVS，播放地址是详情页内联的 `var hlsUrl`（AES-128 HLS）。
  jable,

  /// supjav.com：WordPress，播放地址要先用详情页的 `data-link` 换一次接口。
  supjav,

  /// kissjav.li：KVS，`flashvars.video_url` 是 base64 编码的直链 MP4。
  kissjav,

  /// zh.xhamster.com：Vue 前端，列表与详情都是服务端渲染，但播放地址在
  /// `window.initials` 里并且是**十六进制混淆**过的（解密见 `JavApi`）。
  xhamster,
}

/// 首页上一个分区（就是站点的一个列表页）。
class JavSection {
  const JavSection(this.titleKey, this.path);

  /// `localizedHomeSectionTitle` 认得的文案键（形如 `jav:new`）。
  final String titleKey;

  /// 列表页路径，例如 `/zh/release`。
  final String path;
}

class JavSite {
  const JavSite({
    required this.kind,
    required this.host,
    required this.label,
    this.mirrors = const <String>[],
    this.requiresVerification = false,
    this.prefix = '',
    this.sections = const <JavSection>[],
  });

  final JavSiteKind kind;

  /// 站点主机名。这是一个**默认值**：用户在自己的镜像站/其它语言站里填了别的主机时，
  /// [javSiteFor] 会返回一个换了主机的副本，所以地址不必写死在这里。
  final String host;

  /// 额外认得的镜像域名（同族子域不用写在这里，见 [domainFamily]）。
  final List<String> mirrors;

  /// 界面上显示的名字。
  final String label;

  /// 是否被 Cloudflare 挡着：需要在应用内先过一次人机验证才能抓页面。
  final bool requiresVerification;

  /// 站点语言前缀（missav 要 `/zh` 才会返回中文标题与简介）。
  final String prefix;

  /// 首页分区列表。
  final List<JavSection> sections;

  String get baseUrl => 'https://$host';

  /// 站点根地址 + 语言前缀，例如 `https://missav.ai/zh`。
  String get localizedBaseUrl => '$baseUrl$prefix';

  /// 域名族：`zh.xhamster.com` → `xhamster.com`。
  ///
  /// 靠它才能「不必把地址内嵌在软件里」——用户填 `jp.xhamster.com` / `www.xhamster.com`
  /// 这类同族主机时会被识别成同一个源，后续请求也全部发往用户填的那个主机。
  String get domainFamily {
    final parts = host.split('.');
    return parts.length <= 2 ? host : parts.sublist(parts.length - 2).join('.');
  }

  /// 这个源认不认得 [host]（按域名族 + [mirrors] 判断）。
  bool matchesHost(String host) {
    final bare = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (bare == this.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '')) return true;
    for (final candidate in [domainFamily, ...mirrors]) {
      if (bare == candidate || bare.endsWith('.$candidate')) return true;
    }
    return false;
  }

  /// 把同族里用户填的主机套到这个源上。
  JavSite withHost(String newHost) {
    if (newHost == host) return this;
    return JavSite(kind: kind, host: newHost, label: label, mirrors: mirrors, requiresVerification: requiresVerification, prefix: prefix, sections: sections);
  }
}

/// 内置的 AV 视频源。顺序即「设置 → 站点」与站点选择器里的顺序。
const javSites = <JavSite>[
  JavSite(
    kind: JavSiteKind.missav,
    host: 'missav.ai',
    label: 'MissAV',
    requiresVerification: true,
    prefix: '/zh',
    sections: [
      JavSection('jav:new', '/zh/new'),
      JavSection('jav:latest', '/zh/release'),
      JavSection('jav:uncensored', '/zh/uncensored-leak'),
      JavSection('jav:subtitles', '/zh/chinese-subtitle'),
    ],
  ),
  JavSite(
    kind: JavSiteKind.jable,
    host: 'jable.tv',
    label: 'Jable',
    requiresVerification: true,
    sections: [
      JavSection('jav:latest', '/latest-updates/'),
      JavSection('jav:hot', '/hot/'),
      // 站点顶部导航里的另一个列表页（新作）。
      JavSection('全新上市', '/new-release/'),
      // 站点「按主題」里的常用主题（`/tags/xxx/`，每个都是一份影片列表）。
      // 标题直接用站点自己的中文名：这些是站点特有的分类，没有也不该有 l10n 键
      // （`localizedHomeSectionTitle` 找不到 l10n 时会原样显示）。
      // 分区在界面上是**按需加载**的：只有被选中时才会去抓它的第一页。
      JavSection('巨乳', '/tags/big-tits/'),
      JavSection('熟女', '/tags/mature-woman/'),
      JavSection('中出', '/tags/creampie/'),
      JavSection('口交', '/tags/blowjob/'),
      JavSection('黑絲', '/tags/black-pantyhose/'),
      JavSection('校服', '/tags/school-uniform/'),
      JavSection('女僕', '/tags/maid/'),
      JavSection('Cosplay', '/tags/Cosplay/'),
    ],
  ),
  JavSite(
    kind: JavSiteKind.supjav,
    host: 'supjav.com',
    label: 'SupJav',
    requiresVerification: true,
    sections: [
      JavSection('jav:new', '/'),
      JavSection('jav:popular', '/popular'),
      JavSection('jav:uncensored', '/category/uncensored-jav'),
      JavSection('jav:subtitles', '/category/chinese-subtitles'),
      JavSection('jav:amateur', '/category/amateur'),
    ],
  ),
  JavSite(
    kind: JavSiteKind.kissjav,
    host: 'kissjav.li',
    label: 'KissJAV',
    sections: [
      JavSection('jav:latest', '/latest-updates/'),
      JavSection('jav:popular', '/most-popular/'),
      JavSection('jav:topRated', '/top-rated/'),
    ],
  ),
  JavSite(
    kind: JavSiteKind.xhamster,
    host: 'zh.xhamster.com',
    label: 'xHamster',
    // 列表页都是路径式分页（`/newest/2`），只留最常用的几个分区（站点自己的中文叫法）。
    sections: [
      JavSection('最新', '/newest'),
      JavSection('最好', '/best'),
      JavSection('日本', '/categories/japanese'),
      JavSection('素人', '/categories/amateur'),
      JavSection('人妻', '/categories/wife'),
      JavSection('无码', '/categories/uncensored'),
    ],
  ),
];

/// 找到 [baseUrl] 对应的 AV 源（不是 AV 源时返回 null）。
///
/// 按**域名族**识别（`jp.xhamster.com`、`www.xhamster.com` 都算 xHamster），并把用户
/// 填的主机带回给调用方，这样分区/详情/播放地址全走用户填的那个地址 —— 内置列表里
/// 写的主机只是默认值，不是唯一可用的地址。
JavSite? javSiteFor(String? baseUrl) {
  final text = (baseUrl ?? '').trim();
  if (text.isEmpty) return null;
  var uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) uri = Uri.tryParse('https://$text');
  final host = uri?.host ?? '';
  if (host.isEmpty) return null;
  for (final site in javSites) {
    if (site.matchesHost(host)) return site.withHost(host);
  }
  return null;
}

/// AV 源的列表页文案键 → l10n 查表用的短键（`jav:new` → `new`）。
String? javSectionKey(String title) => title.startsWith('jav:') ? title.substring(4) : null;
