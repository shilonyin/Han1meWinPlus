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
    // 显式给上应用图标，免得这一页只有文字、跟关于页两张皮。
    return LicensePage(
      applicationName: appName,
      applicationVersion: version,
      applicationIcon: Image.asset('assets/logo.png', width: 96, height: 96, filterQuality: FilterQuality.high),
    );
  }
}
