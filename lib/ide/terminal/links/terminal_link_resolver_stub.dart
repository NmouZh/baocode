import 'terminal_link_parsing.dart';

/// The web has no file system to resolve links on.
OperatingSystem get hostOperatingSystem => OperatingSystem.linux;

String? get hostUserHome => null;

Future<bool?> statPath(String path) async => null;

/// The web has no `wsl.exe` to ask where a WSL path is: the path it was
/// given, which resolves nowhere.
Future<String> wslPath(String path) async => path;
