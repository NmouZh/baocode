import 'dart:convert';
import 'dart:io';

import '../terminal_profiles.dart';
import 'terminal_link_parsing.dart';

OperatingSystem get hostOperatingSystem => Platform.isWindows
    ? OperatingSystem.windows
    : Platform.isMacOS
    ? OperatingSystem.macintosh
    : OperatingSystem.linux;

String? get hostUserHome =>
    Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];

/// Whether [path] is a folder (true), a file (false) or nothing (null),
/// following symbolic links.
Future<bool?> statPath(String path) async {
  try {
    return switch ((await FileStat.stat(path)).type) {
      FileSystemEntityType.notFound => null,
      FileSystemEntityType.directory => true,
      _ => false,
    };
  } on FileSystemException {
    return null;
  }
}

/// Where the WSL path [path] is on Windows, as upstream's
/// `ITerminalBackend.getWslPath` asks the pty host's: `wslpath -w`, run in
/// the default distribution.
///
/// Whatever stops the question from being asked answers with the path as it
/// is, and so nothing resolves: another system, no `wsl.exe`, or `wslpath`
/// itself failing. Upstream answers so as well. It also skips the command
/// below build 17063, which added `wslpath`; no build number is read here,
/// since that build's `wsl.exe` fails the question the same way.
Future<String> wslPath(String path) async {
  if (!Platform.isWindows) return path;
  final wslExe = windowsWslExePath(Platform.environment);
  if (!File(wslExe).existsSync()) return path;
  try {
    final result = await Process.run(
      wslExe,
      ['-e', 'wslpath', '-w', path],
      // A drive's paths are ASCII; a path within one need not be, and
      // upstream reads `wslpath`'s output as UTF-8 too.
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return path;
    final converted = (result.stdout as String).trim();
    return converted.isEmpty ? path : converted;
  } on ProcessException {
    return path;
  }
}
