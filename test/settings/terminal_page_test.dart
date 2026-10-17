import 'dart:io';

import 'package:baocode/ide/terminal/terminal_profiles.dart';
import 'package:baocode/ide/terminal/terminal_shell.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:baocode/settings/pages/terminal_page.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _wslExe = r'C:\Windows\System32\wsl.exe';
const _systemShell =
    r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';

/// The shells a Windows has: two of its own, then two WSL distributions,
/// as `detectTerminalProfiles` lists them.
Future<TerminalProfiles> _windows({Object? configured}) async => (
  profiles: const [
    TerminalProfile(
      name: 'PowerShell',
      path: r'C:\Program Files\PowerShell\7\pwsh.exe',
    ),
    TerminalProfile(
      name: 'Command Prompt',
      path: r'C:\Windows\System32\cmd.exe',
    ),
    TerminalProfile(
      name: 'Ubuntu (WSL)',
      path: _wslExe,
      args: ['-d', 'Ubuntu'],
    ),
    TerminalProfile(
      name: 'Debian (WSL)',
      path: _wslExe,
      args: ['-d', 'Debian'],
    ),
  ],
  systemShell: (executable: _systemShell, arguments: const <String>[]),
);

void main() {
  late Directory data;
  late UserSettings settings;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-terminal-page');
    settings = UserSettings(p.join(data.path, 'settings.json'));
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await data.delete(recursive: true);
  });

  /// Lets the disk catch up until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('timed out');
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Future<TerminalProfiles> Function({Object? configured}) detect,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalSettingsPage(
            settings: settings,
            os: TerminalOs.windows,
            detect: detect,
          ),
        ),
      ),
    );
    // The shells are found asynchronously: until they are, the page says
    // that it is looking for them.
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      if (find.byType(SettingsRow).evaluate().isNotEmpty) break;
    }
  }

  /// The name of the row whose tick is shown.
  String ticked(WidgetTester tester) => tester
      .widget<SettingsRow>(
        find.ancestor(
          of: find.byIcon(Codicons.check),
          matching: find.byType(SettingsRow),
        ),
      )
      .label;

  testWidgets("a Windows' shells and its WSL distributions are listed, the "
      "system's own first; a choice is kept in settings.json", (tester) async {
    const key = 'terminal.integrated.defaultProfile.windows';
    await pumpPage(tester, _windows);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('WSL'), findsOneWidget);
    expect(find.text('Ubuntu (WSL)'), findsOneWidget);
    expect(find.text('Debian (WSL)'), findsOneWidget);
    // The shell of the system, with no profile set.
    expect(ticked(tester), 'System default');
    expect(settings[key], isNull);

    await tester.tap(find.text('Ubuntu (WSL)'));
    await settle(tester, () => settings[key] == 'Ubuntu (WSL)');
    expect(
      File(settings.path).readAsStringSync(),
      contains('"terminal.integrated.defaultProfile.windows": "Ubuntu (WSL)"'),
    );
    await tester.pump();
    expect(ticked(tester), 'Ubuntu (WSL)');

    // The system's shell again: the setting taken away.
    await tester.tap(find.text('System default'));
    await settle(tester, () => settings[key] == null);
    await tester.pump();
    expect(ticked(tester), 'System default');
  });

  testWidgets('a Windows with no distribution says so', (tester) async {
    await pumpPage(
      tester,
      ({Object? configured}) async => (
        profiles: const [
          TerminalProfile(
            name: 'Command Prompt',
            path: r'C:\Windows\System32\cmd.exe',
          ),
        ],
        systemShell: (
          executable: r'C:\Windows\System32\cmd.exe',
          arguments: const <String>[],
        ),
      ),
    );
    expect(find.text('WSL'), findsOneWidget);
    expect(find.text('No WSL distribution was found'), findsOneWidget);
    expect(
      find.text('Install one (wsl --install) and open this page again.'),
      findsOneWidget,
    );
  });

  testWidgets('shells that cannot be found are shown as none found', (
    tester,
  ) async {
    await pumpPage(
      tester,
      ({Object? configured}) async => throw StateError('no shells'),
    );
    expect(find.text('No shell was found on this system.'), findsOneWidget);
  });
}
