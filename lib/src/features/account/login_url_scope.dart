import '../../data/remote/windows_connection_factory.dart';

/// 登录页的「是否还停在登录页上」判断（抽出来是为了可测）。
///
/// 为什么不写成 `url.host != login.host`：站点已把 `hanime1.com` 301 到
/// `hanime1.me`，而用户设置里存的可能还是 `.com`。两边域名不同时那个条件**恒为真**，
/// 于是轮询每 2 秒就认为「已离开登录页」并强制采集一次 cookie。
///
/// 用户能直接看到的后果：密码输错时站点正要显示「账号或密码错误」，应用却把这一轮
/// 当成登录完成去抓账号资料，抓不到就抛 `Account profile is unavailable` ——
/// **站点那条提示被盖住**，而应用自己那条每隔两秒重复弹一次。
///
/// 判据是「同一站点 + 同一路径」：host 只要属于同一站群（或完全相等）就算还在。
bool isStillOnLoginPage({required Uri current, required String base}) {
  if (current.host.isEmpty) return false;
  final login = Uri.tryParse('$base/login');
  if (login == null || login.host.isEmpty) return false;
  if (!isSameSiteHost(current.host, login.host)) return false;
  return current.path == login.path;
}

/// 两个主机是否属于同一站点。
///
/// `www.` 前缀忽略；此外 hanime 站群的三个镜像域名（`.com` / `.me` / `hanimeone.me`）
/// 是同一站点、登录态互通（站点自己在它们之间跳转），也视为同一站点。
bool isSameSiteHost(String a, String b) {
  String bare(String host) => host.toLowerCase().startsWith('www.') ? host.toLowerCase().substring(4) : host.toLowerCase();
  final left = bare(a);
  final right = bare(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  return WindowsConnectionFactory.hanimeHosts.contains(left) &&
      WindowsConnectionFactory.hanimeHosts.contains(right);
}
