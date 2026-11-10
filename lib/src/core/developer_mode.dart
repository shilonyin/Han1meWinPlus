import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// 开发者模式的全局只读标志。
///
/// 封面组件（`AppCachedNetworkImage`）是底层共享 widget。
/// 它会被无 ProviderScope 的宿主直接渲染。
/// 那些宿主是 widget 测试与独立播放窗口。
/// 它们读不了 `settingsProvider`。
/// 所以这里放一个全局 [ValueNotifier]。
/// 由 `AppStartupEffects` 在设置变化时单向同步。
/// 图片层只 `developerMode.value` 读一下。
/// 这样图片层不反向依赖设置层。
///
/// 只用 `developerMode.value`，不用 `ValueListenableBuilder`。
/// 切换设置时整页会重建。
/// 不必给每张卡片挂监听。
/// 这样能省掉上千个订阅。
final ValueNotifier<bool> developerMode = ValueNotifier<bool>(false);

/// 开发者模式下所有封面的占位色。
///
/// 用一支中性深灰。
/// 它和封面加载失败时的占位一致（见各处 `errorWidget`）。
/// 这样纯色代替封面看起来就是图还没来。
/// 不会像一块突兀的色块。
const developerCoverColor = Color(0xFF3D3540);

/// 1×1 的不透明 PNG（开发者模式占位色），给需要 `ImageProvider` 的入口用。
///
/// `appNetworkImage` 与 `appCachedImage` 返回的是 provider 而不是 widget。
/// 它们没法直接换成 `ColoredBox`。
/// 给它一张内存里的纯色小图即可。
/// 头像、背景、`CoverImage` 与 `precacheImage` 都不发网络请求。
/// 这张 PNG 由 PIL 生成（1×1 RGBA #3D3540）。
/// 它是合法的完整 PNG，不用手拼字节。
final Uint8List _solidPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOwNXX4DwADFwGynWxwdgAAAABJRU5ErkJggg==',
);

/// 纯色占位图的 provider；每次返回同一个实例以免重复解码。
final ImageProvider developerSolidImage = MemoryImage(_solidPixel);
