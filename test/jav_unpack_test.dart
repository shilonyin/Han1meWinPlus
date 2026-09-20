import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/jav/dean_edwards.dart';

/// missav 播放页里真实抓到的一段 packer 脚本（2026-09-20）。
///
/// 解开后应当是 `source`（主列表）/`source842`（720p）/`source1280`（1080p）
/// 三个变量指向同一个 UUID 目录下的三份播放列表。
const _missavPacker = r"""eval(function(p,a,c,k,e,d){e=function(c){return c.toString(36)};if(!''.replace(/^/,String)){while(c--){d[c.toString(a)]=k[c]||c.toString(a)}k=[function(e){return d[e]}];e=function(){return'\\w+'};c=1};while(c--){if(k[c]){p=p.replace(new RegExp('\\b'+e(c)+'\\b','g'),k[c])}}return p}('f=\'8://7.6/5-4-3-2-1/e.0\';d=\'8://7.6/5-4-3-2-1/c/9.0\';b=\'8://7.6/5-4-3-2-1/a/9.0\';',16,16,'m3u8|3f83eead9b2c|b944|4234|a752|e4a667e0|com|surrit|https|video|1080p|source1280|720p|source842|playlist|source'.split('|'),0,{}))""";

void main() {
  test('解开 missav 的 packer，拿到三档播放列表', () {
    final unpacked = unpackDeanEdwards(_missavPacker);
    expect(unpacked, isNotNull);
    expect(unpacked, contains("source='https://surrit.com/e4a667e0-a752-4234-b944-3f83eead9b2c/playlist.m3u8'"));
    expect(unpacked, contains("source842='https://surrit.com/e4a667e0-a752-4234-b944-3f83eead9b2c/720p/video.m3u8'"));
    expect(unpacked, contains("source1280='https://surrit.com/e4a667e0-a752-4234-b944-3f83eead9b2c/1080p/video.m3u8'"));
  });

  test('不是 packer 的脚本返回 null', () {
    expect(unpackDeanEdwards('const source = "https://example.com/a.m3u8"'), isNull);
    expect(unpackDeanEdwards(''), isNull);
  });
}
