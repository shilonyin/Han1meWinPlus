import 'dart:async';
import 'dart:io';

/// 一次请求把**所有**候选地址都试过了，一个都没连上。
///
/// 不直接把 [SocketException] 抛给界面，是因为原始异常对用户毫无意义：
/// `HTTP connection timed out after 0:00:20.000000, host: hanime1.me, port: 443`
/// 既看不出是内置地址全挂，也看不出该动哪里。带上 [host] 和 [attempts] 之后，
/// 界面能说清「这个站点的节点全不通」，并直接给出改代理的入口。
///
/// [lastError] 保留最后一个候选的真实异常，日志里仍然查得到根因。
class NetworkUnreachableException implements Exception {
  const NetworkUnreachableException({
    required this.host,
    required this.attempts,
    this.lastError,
  });

  /// 请求的目标域名。
  final String host;

  /// 试过的候选数量（内置地址 + DoH 结果 + 域名兜底）。
  final int attempts;

  /// 最后一个候选失败的原始异常。
  final Object? lastError;

  /// 把连接期异常归一化成本类型；其它异常原样抛出。
  ///
  /// 只认这四类：[SocketException]（连不上／超时／被重置）、[TimeoutException]
  /// （我们自己的 `.timeout` 兜底）、[HttpException]（握手期协议错误）、
  /// [HandshakeException]（TLS 握手失败，它不继承自 [SocketException]）。认不出的
  /// 继续往上抛 —— 不能拿「网络不通」遮住真正的 bug。
  static Future<T> guard<T>(
    String host,
    int attempts,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on NetworkUnreachableException {
      rethrow;
    } catch (error, stackTrace) {
      if (error is SocketException || error is TimeoutException || error is HttpException || error is HandshakeException) {
        Error.throwWithStackTrace(
          NetworkUnreachableException(host: host, attempts: attempts, lastError: error),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  /// 面向日志的调试串。界面上的文案一律走 l10n（见 `appErrorTitle`），不读这个。
  @override
  String toString() => 'NetworkUnreachableException($host, $attempts candidates)';
}
