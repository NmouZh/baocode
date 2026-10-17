import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ide/terminal/pty.dart' show ptySupported, terminalProfiles;
import '../../ide/terminal/terminal_profiles.dart';
import '../../ide/terminal/terminal_shell.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../user_settings.dart';
import 'settings_widgets.dart';

/// Settings → Terminal: the shell a new terminal starts in. On Windows each
/// WSL distribution `wsl.exe -l -q` lists is here too, in a group of its
/// own, apart from the system's own shells.
///
/// The choice is `terminal.integrated.defaultProfile.<os>` in settings.json,
/// the setting the terminal panel's own Select Default Profile writes and
/// VS Code reads; no setting at all is the system's shell, which is what the
/// profile service starts when none is set.
class TerminalSettingsPage extends StatefulWidget {
  const TerminalSettingsPage({super.key, this.settings, this.os, this.detect});

  /// settings.json; none under test, where a choice is not kept.
  final UserSettings? settings;

  /// The system whose shells are listed; the app's own by default.
  final TerminalOs? os;

  /// Finds the shells; the platform's own by default, which reads the disk
  /// and, on Windows, runs `wsl.exe`.
  final Future<TerminalProfiles> Function({Object? configured})? detect;

  @override
  State<TerminalSettingsPage> createState() => _TerminalSettingsPageState();
}

class _TerminalSettingsPageState extends State<TerminalSettingsPage> {
  late final TerminalOs _os = widget.os ?? terminalOsOf(defaultTargetPlatform);

  /// The setting this system's choice is kept in, as VS Code names it.
  String get _key => terminalDefaultProfileKey(_os);

  /// The shells, found once: the platform's detection reads the disk and
  /// runs `wsl.exe`, which is not done again on every frame.
  late final Future<TerminalProfiles> _found = _detect();

  /// A detection that fails is shown as none found: this is a list to choose
  /// from, not a report of what went wrong.
  Future<TerminalProfiles> _detect() async =>
      (widget.detect ?? terminalProfiles)(
        configured: widget.settings?[terminalProfilesKey(_os)],
      );

  /// The profile the setting names; null: the system's shell.
  String? get _default => switch (widget.settings?[_key]) {
    final String name when name.isNotEmpty => name,
    _ => null,
  };

  /// Makes [profile] the default; null: the system's shell, which is the
  /// setting taken away, as a default is left unwritten.
  void _setDefault(TerminalProfile? profile) {
    final settings = widget.settings;
    if (settings == null) return;
    unawaited(
      settings.update(_key, profile?.name).catchError((Object error) {
        // A settings.json that does not parse is left as it is; the window
        // shows its error.
        debugPrint('$_key not kept: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.settings ?? Listenable.merge(const []),
      builder: (context, _) => FutureBuilder<TerminalProfiles>(
        future: _found,
        builder: (context, snapshot) => SettingsPage(
          title: l10n.settingsSectionTerminal,
          description: l10n.termSettingsDescription,
          children: _cards(context, snapshot),
        ),
      ),
    );
  }

  /// The page's cards: the shells, or where they are not, which is no
  /// terminals on the web, a detection that failed, or one still being
  /// looked for.
  List<Widget> _cards(
    BuildContext context,
    AsyncSnapshot<TerminalProfiles> snapshot,
  ) {
    final l10n = context.l10n;
    if (!ptySupported) return [_notice(l10n.termSettingsDesktopOnly)];
    if (snapshot.error != null) return [_notice(l10n.termSettingsNone)];
    final found = snapshot.data;
    // Nothing yet: the first frame, before the shells have been found.
    if (found == null) return [_notice(l10n.termSettingsDetecting)];
    return _children(context, found);
  }

  /// The cards: the system's shell (what the setting left unwritten means),
  /// then this system's shells, then the WSL distributions of a Windows.
  List<Widget> _children(BuildContext context, TerminalProfiles found) {
    final l10n = context.l10n;
    final wsl = [
      for (final profile in found.profiles)
        if (profile.isWslDistribution) profile,
    ];
    final shells = [
      for (final profile in found.profiles)
        if (!profile.isWslDistribution) profile,
    ];
    return [
      SettingsCard(children: [_systemRow(context, found.systemShell)]),
      if (shells.isNotEmpty)
        SettingsGroup(
          title: _os == TerminalOs.windows
              ? l10n.termSettingsWindowsGroup
              : l10n.termSettingsSystemGroup,
          children: [for (final profile in shells) _profileRow(profile)],
        ),
      if (_os == TerminalOs.windows)
        SettingsGroup(
          title: l10n.termSettingsWslGroup,
          description: wsl.isEmpty ? null : l10n.termSettingsWslDescription,
          children: wsl.isEmpty
              ? [
                  SettingsRow(
                    label: l10n.termSettingsWslNone,
                    description: l10n.termSettingsWslNoneDetail,
                  ),
                ]
              : [for (final profile in wsl) _profileRow(profile)],
        ),
    ];
  }

  /// The shell this system starts with no profile set: choosing it takes
  /// the setting away again.
  Widget _systemRow(BuildContext context, TerminalShell shell) {
    final selected = _default == null;
    return SettingsRow(
      label: context.l10n.termSettingsSystemDefault,
      description: shell.executable.isEmpty ? null : shell.executable,
      onTap: selected ? null : () => _setDefault(null),
      trailing: _check(selected),
    );
  }

  /// One shell a new terminal can start: the tick on the one the setting
  /// names.
  Widget _profileRow(TerminalProfile profile) {
    final selected = _default == profile.name;
    return SettingsRow(
      label: profile.name,
      // The shell it starts, as the panel's own pick shows it.
      description: [profile.path, ...profile.args].join(' '),
      onTap: selected ? null : () => _setDefault(profile),
      trailing: _check(selected),
    );
  }

  /// The tick of the row that is in use, and the room for one where the
  /// rows would otherwise end at a different place.
  Widget _check(bool selected) => SizedBox(
    width: 16,
    child: selected
        ? Icon(Codicons.check, size: 14, color: AppColors.accent)
        : null,
  );

  /// Where the shells are not, in place of the cards that list them.
  Widget _notice(String text) => SettingsCard(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(text, style: SettingsText.description),
      ),
    ],
  );
}
