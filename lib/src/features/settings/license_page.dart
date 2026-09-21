import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_identity.dart';
import '../../core/app_info.dart';

class AppLicensePage extends ConsumerWidget {
  const AppLicensePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(packageInfoProvider).valueOrNull?.version ?? '';
    // LicensePage 默认不画图标（Flutter 里的 _defaultApplicationIcon 直接返回 null），
    // 这里放设计稿的整张锁标（图标 + 字标）—— 所以 applicationName 留空，
    // 否则锁标里的字标与它上面那行同名文字会重复。
    return LicensePage(
      applicationName: '',
      applicationVersion: version,
      applicationIcon: Image.asset('assets/logo_lockup.png', height: 56, filterQuality: FilterQuality.high, semanticLabel: appName),
    );
  }
}
