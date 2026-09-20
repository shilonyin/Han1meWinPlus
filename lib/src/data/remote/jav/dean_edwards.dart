/// Dean Edwards 的 JavaScript packer 解码器。
///
/// missav 的播放页把播放地址（`source` / `source842` / `source1280`）藏在一段
/// packer 打包过的内联脚本里，形态是：
///
/// ```js
/// eval(function(p,a,c,k,e,d){…}('f=\'8://7.6/5-4-3-2-1/e.0\';',16,16,'m3u8|uuid|…'.split('|'),0,{}))
/// ```
///
/// 解码就是把 payload 里每个 base-N 词换成词表里同下标的词；词表项为空时用
/// 「下标本身的 base-N 写法」补位（这正是原版解码器 `e(c)` 的行为）。
library;

/// 解开 [source] 里第一段 packer 脚本；不是 packer（或解不开）时返回 null。
String? unpackDeanEdwards(String source) {
  final match = RegExp(r"""}\s*\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'""", dotAll: true).firstMatch(source);
  if (match == null) return null;
  final payload = match.group(1)!.replaceAll(r"\'", "'");
  final radix = int.tryParse(match.group(2)!) ?? 36;
  final count = int.tryParse(match.group(3)!) ?? 0;
  final keys = match.group(4)!.split('|');
  if (radix < 2 || radix > 36 || count <= 0) return null;
  final table = List<String>.generate(count, (index) => index < keys.length && keys[index].isNotEmpty ? keys[index] : _baseN(index, radix));
  return payload.replaceAllMapped(RegExp(r'\b[0-9a-z]+\b'), (token) {
    final value = token.group(0)!;
    final index = int.tryParse(value, radix: radix);
    return index == null || index < 0 || index >= table.length ? value : table[index];
  });
}

String _baseN(int value, int radix) {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  if (value <= 0) return '0';
  var remaining = value;
  final buffer = <String>[];
  while (remaining > 0) {
    buffer.insert(0, digits[remaining % radix]);
    remaining ~/= radix;
  }
  return buffer.join();
}
