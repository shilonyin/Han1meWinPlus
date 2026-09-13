import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const androidDefaultDownloadPath = '/storage/emulated/0/Android/data/com.liar.han1meplus/files/Download/';

bool isAndroidDownloadPath(String path) => path.startsWith('/storage/emulated/0/');

/// Folder under %APPDATA% that holds settings, history and downloads.
///
/// Windows used to resolve this through `getApplicationSupportDirectory`, which
/// builds the path out of the executable's CompanyName/ProductName version
/// resource. Adding a VERSIONINFO block therefore silently moved the folder and
/// orphaned every existing setting, account and watch history. The name is
/// pinned here instead so it cannot move again.
const _windowsStorageFolder = 'han1me_win_plus';

Future<Directory> appStorageDirectory() async {
  final directory = await _storageDirectory();
  await directory.create(recursive: true);
  return directory;
}

Future<Directory> _storageDirectory() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) return Directory(path.join(appData, _windowsStorageFolder));
  }
  return getApplicationSupportDirectory();
}

Future<Directory> downloadStorageDirectory() async {
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) return Directory(path.join(external.path, 'Download'));
  }
  return Directory(path.join((await appStorageDirectory()).path, 'Download'));
}

Future<String> resolveDefaultDownloadPath() async {
  final directory = await downloadStorageDirectory();
  await directory.create(recursive: true);
  return directory.path;
}

Future<String> normalizeDownloadPath(String value) async {
  if (value.trim().isEmpty || (!Platform.isAndroid && isAndroidDownloadPath(value))) {
    return resolveDefaultDownloadPath();
  }
  var resolved = value.trim();
  if (Platform.isWindows) {
    final environment = {for (final entry in Platform.environment.entries) entry.key.toLowerCase(): entry.value};
    resolved = resolved.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) => environment[match.group(1)!.toLowerCase()] ?? match.group(0)!);
  } else if (resolved == '~' || resolved.startsWith('~/')) {
    final home = Platform.environment['HOME'];
    if (home != null) resolved = path.join(home, resolved.substring(2));
  }
  return Directory(resolved).absolute.path;
}

String platformDownloadPathHint(String fallbackHint) {
  if (Platform.isWindows) return r'%APPDATA%\han1me_win_plus\Download';
  if (Platform.isMacOS) return '~/Library/Application Support/han1me_plus/Download';
  if (Platform.isLinux) return '~/.local/share/han1me_plus/Download';
  if (Platform.isIOS) return '~/Documents/Download';
  return fallbackHint;
}
