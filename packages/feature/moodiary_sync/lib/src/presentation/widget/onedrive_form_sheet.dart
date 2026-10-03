import 'dart:async';

import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_sync/src/application/sync_runner.dart';
import 'package:moodiary_sync/src/data/model/sync_provider.dart';
import 'package:moodiary_sync/src/data/onedrive_auth.dart';
import 'package:moodiary_sync/src/data/sync.dart';
import 'package:mui/mui.dart';
import 'package:url_launcher/url_launcher.dart';

class OneDriveFormSheet extends StatefulWidget {
  const OneDriveFormSheet({
    super.key,
    required this.initial,
    required this.configured,
  });

  final List<String> initial;
  final bool configured;

  @override
  State<OneDriveFormSheet> createState() => _OneDriveFormSheetState();

  static Future<bool?> show(BuildContext context) async {
    final backend = getIt<IRemoteSyncBackend>(
      instanceName: SyncProviderIds.onedrive,
    );
    final (initial, configured) = await (
      backend.savedOptions(),
      backend.isReady(),
    ).wait;
    if (!context.mounted) return null;
    return MSheet.show<bool>(
      context,
      builder: (_) => OneDriveFormSheet(initial: initial, configured: configured),
    );
  }
}

class _OneDriveFormSheetState extends State<OneDriveFormSheet> {
  late final TextEditingController _clientCtl;

  late final _backend = getIt<IRemoteSyncBackend>(
    instanceName: SyncProviderIds.onedrive,
  );
  late final bool _configured = widget.configured;

  bool _saving = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    final opts = widget.initial;
    _clientCtl = TextEditingController(text: opts.isNotEmpty ? opts[0] : '');
  }

  @override
  void dispose() {
    _clientCtl.dispose();
    super.dispose();
  }

  bool get _signedIn => widget.initial.length > 1 && widget.initial[1].isNotEmpty;

  Future<void> _save() async {
    if (_saving) return;
    final clientId = _clientCtl.text.trim();
    if (clientId.isEmpty) {
      toast.error(message: l10n.sync.onedriveClientIdRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      // Keep the stored tokens when only the client id text changed.
      final tokens = _signedIn
          ? [
              widget.initial[1],
              widget.initial[2],
              widget.initial.length > 3 ? widget.initial[3] : '',
            ]
          : const <String>['', '', ''];
      await _backend.saveOptions([clientId, ...tokens]);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _signIn() async {
    final clientId = _clientCtl.text.trim();
    if (clientId.isEmpty) {
      toast.error(message: l10n.sync.onedriveClientIdRequired);
      return;
    }
    setState(() => _signingIn = true);
    try {
      final tokens = await showOneDriveSignInSheet(context, clientId: clientId);
      if (tokens == null || !mounted) return;
      await _backend.saveOptions([clientId, ...tokens]);
      getIt<SyncRunner>().resetHealth();
    } finally {
      if (mounted) {
        setState(() => _signingIn = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _signOut() async {
    final l10n = context.l10n;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.sync.onedriveSignOutConfirmTitle,
      message: l10n.sync.onedriveSignOutConfirmMessage,
      confirmLabel: l10n.sync.onedriveSignOut,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await _backend.clearOptions();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MSheetScaffold<bool>(
      title: l10n.sync.backupSyncOnedrive,
      subtitle: _configured
          ? (_signedIn
              ? l10n.sync.onedriveOptionSignedIn
              : l10n.sync.onedriveOptionSignedOut)
          : l10n.sync.backupSyncWebdavNoOption,
      icon: LucideIcons.cloud,
      actions: [
        MAction(label: l10n.common.cancel, value: false, enabled: !_saving),
        MAction(
          label: l10n.common.save,
          isPrimary: true,
          busy: _saving,
          enabled: !_saving,
          onPressed: _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 14,
        children: [
          MField(
            controller: _clientCtl,
            label: l10n.sync.onedriveOptionClientId,
            hintText: l10n.sync.onedriveClientIdHint,
            enabled: !_saving && !_signingIn,
            keyboardType: .url,
            textInputAction: .done,
            onSubmitted: (_) => _save(),
          ),
          FilledButton.icon(
            onPressed: (_saving || _signingIn) ? null : _signIn,
            icon: const Icon(LucideIcons.keyRound, size: 18),
            label: _signingIn
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.theme.colors.onPrimary,
                    ),
                  )
                : Text(l10n.sync.onedriveSignIn),
          ),
          Text(
            l10n.sync.onedriveSetupGuideMessage,
            style: context.theme.typography.bodySmall.onSurfaceVariant,
          ),
          if (_configured)
            MDangerRow(
              label: l10n.sync.onedriveSignOut,
              onPressed: (_saving || _signingIn) ? null : _signOut,
            ),
        ],
      ),
    );
  }
}

/// Runs the OAuth device code flow in a sheet: shows the user code,
/// opens the Microsoft login page and polls until the user finishes.
/// Returns the stored token triple (access, refresh, expiry millis).
Future<List<String>?> showOneDriveSignInSheet(
  BuildContext context, {
  required String clientId,
}) async {
  final auth = OneDriveAuth(RustHttpClient());
  final result = await MSheet.show<_SignInResult>(
    context,
    barrierDismissible: false,
    builder: (sheetContext) => _OneDriveSignInSheet(
      auth: auth,
      clientId: clientId,
    ),
  );
  return result?.tokens;
}

class _SignInResult {
  const _SignInResult(this.tokens);

  final List<String> tokens;
}

class _OneDriveSignInSheet extends StatefulWidget {
  const _OneDriveSignInSheet({required this.auth, required this.clientId});

  final OneDriveAuth auth;
  final String clientId;

  @override
  State<_OneDriveSignInSheet> createState() => _OneDriveSignInSheetState();
}

class _OneDriveSignInSheetState extends State<_OneDriveSignInSheet> {
  OneDriveDeviceFlow? _flow;
  String _status = '';
  String? _error;
  bool _busy = true;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = '';
    });
    try {
      final flow = await widget.auth.startDeviceFlow(widget.clientId);
      if (!mounted) return;
      setState(() {
        _flow = flow;
        _status = l10n.sync.onedriveSignInSubtitle;
        _busy = false;
      });
      unawaited(_openBrowser(flow.verificationUri));
      final token = await widget.auth.pollForToken(
        widget.clientId,
        flow,
        onStatus: (message) {
          if (!mounted) return;
          setState(() => _status = message);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(_SignInResult([
        token.accessToken,
        token.refreshToken,
        '${token.expiry.millisecondsSinceEpoch}',
      ]));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is OneDriveAuthException ? e.message : e.toString();
      });
    }
  }

  Future<void> _openBrowser(String uri) async {
    if (_opened) return;
    _opened = true;
    try {
      await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // The user can still open the link by hand.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final flow = _flow;
    return MSheetScaffold<_SignInResult>(
      title: l10n.sync.onedriveSignIn,
      icon: LucideIcons.keyRound,
      actions: [
        MAction(label: l10n.common.cancel, value: null, enabled: !_busy),
      ],
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 14,
        children: [
          if (flow != null) ...[
            Text(
              flow.userCode,
              style: context.theme.typography.headlineMedium.primary,
              textAlign: .center,
            ),
            Text(
              flow.verificationUri,
              style: context.theme.typography.bodyMedium.primary,
              textAlign: .center,
            ),
            FilledButton.icon(
              onPressed: () => unawaited(_openBrowser(flow.verificationUri)),
              icon: const Icon(LucideIcons.externalLink, size: 18),
              label: Text(l10n.sync.onedriveSetupGuideOpen),
            ),
          ],
          if (_busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_status.isNotEmpty && _error == null)
            Text(
              _status,
              style: context.theme.typography.bodySmall.onSurfaceVariant,
              textAlign: .center,
            ),
          if (_error != null)
            Text(
              l10n.sync.onedriveAuthFailed(error: _error!),
              style: context.theme.typography.bodySmall.error,
              textAlign: .center,
            ),
        ],
      ),
    );
  }
}
