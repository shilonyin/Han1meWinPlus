// 封面缓存 key：去掉服务端现算的签名参数。
//
// 守的是一个实测到的问题：`secure` 的形态是 `<签名>,<过期时间戳>`，后半段由服务器
// 处理该请求时生成，所以同一个视频每次抓页面拿到的封面 URL 都不同。缓存 key 用完整
// URL 时，磁盘缓存永远不命中 —— 实测缓存目录里 167 个文件只有 113 份唯一内容，
// 54 组是同一张图存了两份（两次启动各下一遍），首屏封面因此每次都要重新下载。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/shared/app_image_cache.dart';

void main() {
  test('去掉 secure 签名，保留路径', () {
    expect(
      imageCacheKey('https://vdownload.hembed.com/image/thumbnail/406505h.jpg?secure=HzeyCoSjt2znyaMukMeOjA==,1793414118'),
      'https://vdownload.hembed.com/image/thumbnail/406505h.jpg',
    );
  });

  test('同一张图的两个不同签名 → 同一个 key（这是本函数存在的理由）', () {
    const a = 'https://vdownload.hembed.com/image/thumbnail/406505h.jpg?secure=AAA,1793414118';
    const b = 'https://vdownload.hembed.com/image/thumbnail/406505h.jpg?secure=BBB,1793999999';
    expect(imageCacheKey(a), imageCacheKey(b));
  });

  test('不同图片仍然区分开', () {
    const a = 'https://vdownload.hembed.com/image/thumbnail/406505h.jpg?secure=AAA,1';
    const b = 'https://vdownload.hembed.com/image/thumbnail/166761h.jpg?secure=AAA,1';
    expect(imageCacheKey(a), isNot(imageCacheKey(b)));
  });

  test('无查询串的 URL 原样返回', () {
    const url = 'https://vdownload.hembed.com/image/thumbnail/406505h.jpg';
    expect(imageCacheKey(url), url);
  });

  test('有意义的参数被保留（只去签名类）', () {
    expect(
      imageCacheKey('https://example.com/a.jpg?w=480&secure=XYZ,1'),
      'https://example.com/a.jpg?w=480',
    );
  });

  test('多个签名参数一起去掉', () {
    expect(
      imageCacheKey('https://example.com/a.jpg?token=t&expires=123&sign=s'),
      'https://example.com/a.jpg',
    );
  });

  test('解析不了或非 URL 的输入原样返回（宁可退化成按完整 URL 缓存）', () {
    expect(imageCacheKey('not a url'), 'not a url');
    expect(imageCacheKey(''), '');
  });
}
