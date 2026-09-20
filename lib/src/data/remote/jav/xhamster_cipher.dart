import 'dart:convert';

/// xhamster 的播放地址是**混淆**过的：`window.initials` 里
/// `xplayerSettings.sources.*.url` 给的是十六进制串，解出来才是真正的地址。
///
/// 格式（移植自 yt-dlp 的同名实现，已用真实页面逐字节核对）：
/// * 第 1 个字节是算法编号（1..7）；
/// * 第 2..5 个字节是小端 int32 种子；
/// * 之后每个字节都异或上「伪随机序列」的下一个字节（序列按算法编号推进状态）。
///
/// 全程按 32 位有符号整数回绕运算（Dart 的 int 是 64 位，所以要显式回绕）。
const int _mask32 = 0xFFFFFFFF;

/// 按 32 位有符号整数回绕。
int _i32(int value) => (value & _mask32).toSigned(32);

/// 无符号右移（Dart 的 `>>` 是算术右移，负数会带符号位）。
int _u32Shift(int value, int bits) => (value & _mask32) >> bits;

/// 解一段十六进制密文；不是合法密文（太短 / 奇数位 / 算法编号不认识）时返回 `null`。
String? xhamsterDecipher(String? value) {
  final text = value?.trim() ?? '';
  if (text.length < 12 || text.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) return null;
  final length = text.length ~/ 2;
  final data = List<int>.generate(length, (index) => int.parse(text.substring(index * 2, index * 2 + 2), radix: 16), growable: false);
  final seed = _i32(data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24));
  final _ByteGenerator generator;
  try {
    generator = _ByteGenerator(data[0], seed);
  } on ArgumentError {
    return null;
  }
  final bytes = List<int>.generate(length - 5, (index) => data[index + 5] ^ generator.next(), growable: false);
  return latin1.decode(bytes, allowInvalid: true);
}

/// 按算法编号推进状态并取低 8 位。
class _ByteGenerator {
  _ByteGenerator(this._algorithm, int seed) : _state = _i32(seed) {
    if (_algorithm < 1 || _algorithm > 7) throw ArgumentError('未知的混淆算法：$_algorithm');
  }

  final int _algorithm;
  int _state;

  int next() => _step() & 0xFF;

  int _step() {
    var state = _state;
    switch (_algorithm) {
      case 1: // 线性同余
        return _state = _i32(state * 1664525 + 1013904223);
      case 2: // xorshift32
        state = _i32(state ^ (state << 13));
        state = _i32(state ^ _u32Shift(state, 17));
        return _state = _i32(state ^ (state << 5));
      case 3: // Weyl 序列 + MurmurHash 收尾
        state = _state = _i32(state + 0x9E3779B9);
        state = _i32(state ^ _u32Shift(state, 16));
        state = _i32(state * _i32(0x85EBCA77));
        state = _i32(state ^ _u32Shift(state, 13));
        state = _i32(state * _i32(0xC2B2AE3D));
        return _i32(state ^ _u32Shift(state, 16));
      case 4: // 循环移位 + 乘法
        state = _state = _i32(state + 0x6D2B79F5);
        state = _i32(((state << 7) & _mask32) | _u32Shift(state, 25));
        state = _i32(state + 0x9E3779B9);
        state = _i32(state ^ _u32Shift(state, 11));
        return _i32(state * 0x27D4EB2D);
      case 5: // xorshift + 常量偏移
        state = _i32(state ^ (state << 7));
        state = _i32(state ^ _u32Shift(state, 9));
        state = _i32(state ^ (state << 8));
        return _state = _i32(state + 0xA5A5A5A5);
      case 6: // 线性同余 + 依赖状态的移位
        state = _state = _i32(state * _i32(0x2C9277B5) + _i32(0xAC564B05));
        final mixed = _i32(state ^ _u32Shift(state, 18));
        return _i32(_u32Shift(mixed, _u32Shift(state, 27) & 31));
      default: // 7：Weyl + 乘法混合
        state = _state = _i32(state + _i32(0x9E3779B9));
        var mixed = _i32(state ^ (state << 5));
        mixed = _i32(mixed * _i32(0x7FEB352D));
        mixed = _i32(mixed ^ _u32Shift(mixed, 15));
        return _i32(mixed * _i32(0x846CA68B));
    }
  }
}
