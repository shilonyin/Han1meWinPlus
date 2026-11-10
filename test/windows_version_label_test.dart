import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/settings/log_settings_page.dart';

void main() {
  group('windowsVersionLabel', () {
    test('Win11 的英文 ProductName 仍写 Windows 10，按 Build 号纠正', () {
      expect(
        windowsVersionLabel('"Windows 10 Pro" 10.0 (Build 26300)', true),
        'Windows 11 Pro 10.0 (Build 26300)',
      );
    });

    test('中文版已经写 Windows 11 时原样保留', () {
      expect(
        windowsVersionLabel('"Windows 11 专业版" 10.0 (Build 26300)', true),
        'Windows 11 专业版 10.0 (Build 26300)',
      );
    });

    test('真正的 Win10（Build < 22000）不改', () {
      expect(
        windowsVersionLabel('"Windows 10 Pro" 10.0 (Build 19045)', true),
        'Windows 10 Pro 10.0 (Build 19045)',
      );
    });

    test('Build 22000 边界算 Win11', () {
      expect(
        windowsVersionLabel('"Windows 10 Pro" 10.0 (Build 22000)', true),
        'Windows 11 Pro 10.0 (Build 22000)',
      );
    });

    test('拿不到 Build 号就原样返回', () {
      expect(windowsVersionLabel('Windows 10 Pro', true), 'Windows 10 Pro');
    });

    test('非 Windows 平台原样返回（只去引号）', () {
      expect(windowsVersionLabel('"macOS 15.0"', false), 'macOS 15.0');
    });
  });
}
