import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../logic/profile.dart';
import '../../services/backup.dart';
import '../../services/health_sync.dart';
import '../../state/app_state.dart';
import '../common.dart';

Widget settingsHeader(BuildContext context, String s) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 16, 6),
      child: Text(s, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );

/// Health Connect (Google Fit) on/off and status.
class HealthSection extends StatefulWidget {
  const HealthSection({super.key});

  @override
  State<HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<HealthSection> {
  String? _status;

  @override
  void initState() {
    super.initState();
    HealthSync.instance.status().then((s) {
      if (mounted) setState(() => _status = s);
    }).catchError((_) {
      if (mounted) setState(() => _status = 'missing');
    });
  }

  Future<void> _toggle(bool on) async {
    final app = context.read<AppState>();
    if (!on) {
      await app.setBool('healthOn', false);
      app.setActivity(burned: 0, steps: 0);
      return;
    }
    if (_status != 'installed') {
      await HealthSync.instance.install();
      return;
    }
    final ok = await HealthSync.instance.connect();
    if (!mounted) return;
    if (!ok) {
      toast(context, context.tr('healthDenied'));
      return;
    }
    await app.setBool('healthOn', true);
    await HealthSync.instance.refreshActivity(app);
    HealthSync.instance.scheduleWrite(app);
    if (mounted) toast(context, context.tr('healthConnected'));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final on = app.getBool('healthOn');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      settingsHeader(context, context.tr('healthSection')),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.favorite_outline),
            title: Text(context.tr('healthConnect')),
            subtitle: Text(switch (_status) {
              null => '…',
              'installed' => context.tr('healthSub'),
              'needsUpdate' => context.tr('healthUpdate'),
              _ => context.tr('healthMissing'),
            }),
            value: on,
            onChanged: _toggle,
          ),
          if (on)
            SwitchListTile(
              secondary: const Icon(Icons.local_fire_department_outlined),
              title: Text(context.tr('addExercise')),
              subtitle: Text(context.tr('addExerciseSub')),
              value: app.addExercise,
              onChanged: (v) => app.addExercise = v,
            ),
        ]),
      ),
    ]);
  }
}

/// Google Drive backup plus export/import to a file.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, '${context.tr('failed')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterRestore() async {
    final app = context.read<AppState>();
    app.profile = await Profile.load(app.prefs);
    await app.reload();
    app.touch();
  }

  Future<void> _setClientId() async {
    final app = context.read<AppState>();
    final v = await promptText(context, context.tr('googleClientId'), initial: app.getString('gdriveClientId'), hint: '….apps.googleusercontent.com');
    if (v != null) await app.setString('gdriveClientId', v.trim());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final drive = DriveBackup(app.prefs);
    final last = DateTime.tryParse(app.getString('lastBackup'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      settingsHeader(context, context.tr('backupSection')),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          if (_busy) const LinearProgressIndicator(),
          if (!drive.configured)
            ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(context.tr('driveNotSetUp')),
              subtitle: Text(context.tr('driveNotSetUpSub')),
              onTap: _setClientId,
            )
          else if (!drive.signedIn)
            ListTile(
              leading: const Icon(Icons.add_to_drive),
              title: Text(context.tr('driveSignIn')),
              subtitle: Text(context.tr('driveSignInSub')),
              onTap: _busy ? null : () => _run(() async {
                await drive.signIn();
                app.touch();
              }, context.tr('signedIn')),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: Text(drive.email ?? 'Google'),
              subtitle: Text(last == null ? context.tr('noBackupYet') : '${context.tr('lastBackup')}: ${DateFormat.yMMMd(lang(context)).add_Hm().format(last)}'),
              trailing: TextButton(onPressed: () async {
                await drive.signOut();
                app.touch();
              }, child: Text(context.tr('signOut'))),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(context.tr('backupNow')),
              onTap: _busy ? null : () => _run(() async {
                await drive.upload(await Backup.create(app.prefs));
                app.touch();
              }, context.tr('backupDone')),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(context.tr('restoreDrive')),
              onTap: _busy
                  ? null
                  : () async {
                      if (!await confirm(context, context.tr('restoreQ'), body: context.tr('restoreQBody'))) return;
                      await _run(() async {
                        final data = await drive.download();
                        if (data == null) throw Exception(context.tr('noBackupYet'));
                        await Backup.restore(app.prefs, data);
                        await _afterRestore();
                      }, context.tr('restoreDone'));
                    },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule),
              title: Text(context.tr('autoBackup')),
              subtitle: Text(context.tr('autoBackupSub')),
              value: app.getBool('autoBackup', true),
              onChanged: (v) => app.setBool('autoBackup', v),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: Text(context.tr('exportFile')),
            subtitle: Text(context.tr('exportFileSub')),
            onTap: _busy
                ? null
                : () => _run(() async {
                      final bytes = await Backup.create(app.prefs);
                      final saved = await FilePicker.saveFile(fileName: Backup.fileName(), bytes: bytes, mimeType: 'application/json');
                      if (saved == null) throw Exception(context.tr('cancelled'));
                    }, context.tr('exportDone')),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(context.tr('importFile')),
            onTap: _busy
                ? null
                : () async {
                    final pick = await FilePicker.pickFiles();
                    final bytes = pick.isEmpty ? null : await pick.first.xFile.readAsBytes();
                    if (bytes == null || !context.mounted) return;
                    if (!await confirm(context, context.tr('restoreQ'), body: context.tr('restoreQBody'))) return;
                    await _run(() async {
                      await Backup.restore(app.prefs, bytes);
                      await _afterRestore();
                    }, context.tr('restoreDone'));
                  },
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(context.tr('googleClientId')),
            subtitle: Text(app.getString('gdriveClientId').isEmpty
                ? (DriveBackup.builtInClientId.isEmpty ? context.tr('notSet') : context.tr('builtIn'))
                : app.getString('gdriveClientId'), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: _setClientId,
          ),
        ]),
      ),
    ]);
  }
}
