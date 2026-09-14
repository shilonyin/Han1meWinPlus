import 'dart:ui';

/// 可选硬件解码器：键会直接作为 mpv 的 `hwdec` 值传给播放器，值是对应的说明。
///
/// 「-copy」结尾的是「非直通」模式（解码后拷回内存，兼容性更好但更耗性能）；
/// 选到当前设备不支持的解码器时，mpv 会自动回退到软件解码。
///
/// 只保留仍然有效的解码器：已废弃的（cuda / crystalhd）、效果不稳定的实验性
/// 后端（vulkan），以及本应用用不到的其它平台后端（videotoolbox / mediacodec
/// / vaapi / vdpau / drm / rkmpp）都已移除。
const Map<String, String> hardwareDecodersZh = {
  'auto': '启用任意可用解码器',
  'auto-safe': '启用最佳解码器',
  'auto-copy': '启用带拷贝功能的最佳解码器',
  'd3d11va': 'DirectX11 (Windows 8 及以上)',
  'd3d11va-copy': 'DirectX11 (Windows 8 及以上) (非直通)',
  'dxva2': 'DXVA2 (Windows 7 及以上)',
  'dxva2-copy': 'DXVA2 (Windows 7 及以上) (非直通)',
  'nvdec': 'NVDEC (NVIDIA 独占)',
  'nvdec-copy': 'NVDEC (NVIDIA 独占) (非直通)',
};

/// 与上面一一对应的英文说明（zh_TW 暂用简体说明）
const Map<String, String> hardwareDecodersEn = {
  'auto': 'Enable any available decoder',
  'auto-safe': 'Enable the best decoder',
  'auto-copy': 'Enable the best decoder with copy-back',
  'd3d11va': 'DirectX 11 (Windows 8+)',
  'd3d11va-copy': 'DirectX 11 (Windows 8+) (copy-back)',
  'dxva2': 'DXVA2 (Windows 7+)',
  'dxva2-copy': 'DXVA2 (Windows 7+) (copy-back)',
  'nvdec': 'NVDEC (NVIDIA only)',
  'nvdec-copy': 'NVDEC (NVIDIA only) (copy-back)',
};

/// 默认硬件解码器
const String defaultHardwareDecoder = 'auto-safe';

/// 按语言取解码器说明，没有对应语言时回退到简体中文
Map<String, String> hardwareDecodersFor(Locale locale) => locale.languageCode == 'en' ? hardwareDecodersEn : hardwareDecodersZh;

/// 规整解码器值：旧版本存过已下线的解码器时统一回退到默认值
String knownHardwareDecoder(String? value) => hardwareDecodersZh.containsKey(value) ? value! : defaultHardwareDecoder;
