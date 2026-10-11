import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_di/moodiary_di.dart';
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
    required this.configured,
    this.initialClientId = '',
  });

  final bool configured;

  /// Bereits gespeicherte Client-ID (kann leer sein).
  final String initialClientId;

  @override
  State<OneDriveFormSheet> createState() => _OneDriveFormSheetState();

  static Future<bool?> show(BuildContext context) async {
    final backend = getIt<IRemoteSyncBackend>(
      instanceName: SyncProviderIds.onedrive,
    );
    final (saved, configured) = await (
      backend.savedOptions(),
      backend.isReady(),
    ).wait;
    if (!context.mounted) return null;
    return MSheet.show<bool>(
      context,
      builder: (_) => OneDriveFormSheet(
        configured: configured,
        initialClientId: saved.isNotEmpty ? saved[0] : '',
      ),
    );
  }
}

class _OneDriveFormSheetState extends State<OneDriveFormSheet> {
  late final _backend = getIt<IRemoteSyncBackend>(
    instanceName: SyncProviderIds.onedrive,
  );

  bool _busy = false;
  late final TextEditingController _clientCtl;

  /// True, wenn weder gespeicherte noch eingebaute ID existiert: Dann muss
  /// die eigene Azure-Client-ID von Hand eingetragen werden.
  bool get _needsId =>
      widget.initialClientId.isEmpty &&
      OneDriveAuth.defaultClientId.isEmpty;

  @override
  void initState() {
    super.initState();
    _clientCtl = TextEditingController(
      text: widget.initialClientId.isEmpty
          ? OneDriveAuth.defaultClientId
          : widget.initialClientId,
    );
  }

  @override
  void dispose() {
    _clientCtl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final clientId = _clientCtl.text.trim();
    if (clientId.isEmpty) {
      toast.error(message: l10n.sync.onedriveClientIdRequired);
      return;
    }
    setState(() => _busy = true);
    try {
      final tokens = await showOneDriveSignInSheet(
        context,
        clientId: clientId,
      );
      if (tokens == null || !mounted) return;
      await _backend.saveOptions([clientId, ...tokens]);
      getIt<SyncRunner>().resetHealth();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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
    setState(() => _busy = true);
    try {
      await _backend.clearOptions();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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
      subtitle: widget.configured
          ? l10n.sync.onedriveOptionSignedIn
          : l10n.sync.backupSyncWebdavNoOption,
      icon: LucideIcons.cloud,
      actions: [
        MAction(label: l10n.common.cancel, value: false, enabled: !_busy),
      ],
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 14,
        children: [
          if (_needsId)
            MField(
              controller: _clientCtl,
              label: l10n.sync.onedriveOptionClientId,
              hintText: l10n.sync.onedriveClientIdHint,
              enabled: !_busy,
              keyboardType: .url,
              textInputAction: .done,
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _signIn,
            icon: const Icon(LucideIcons.keyRound, size: 18),
            label: _busy
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
          if (widget.configured)
            MDangerRow(
              label: l10n.sync.onedriveSignOut,
              onPressed: _busy ? null : _signOut,
            ),
        ],
      ),
    );
  }
}

/// Opens the Microsoft sign-in page in the system browser and waits for the
/// loopback callback. Returns the stored token triple
/// (access, refresh, expiry millis).
Future<List<String>?> showOneDriveSignInSheet(
  BuildContext context, {
  required String clientId,
}) async {
  final auth = OneDriveAuth();
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
  String _status = '';
  String? _error;
  bool _busy = true;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = l10n.sync.onedriveSignInSubtitle;
    });
    try {
      final token = await widget.auth.signInWithBrowser(
        widget.clientId,
        openUrl: _openBrowser,
        onStatus: (message) {
          if (!mounted) return;
          setState(() => _status = message);
        },
      );
      if (!mounted || _cancelled) return;
      Navigator.of(context).pop(_SignInResult([
        token.accessToken,
        token.refreshToken,
        '${token.expiry.millisecondsSinceEpoch}',
      ]));
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() {
        _busy = false;
        _error = e is OneDriveAuthException ? e.message : e.toString();
      });
    } finally {
      widget.auth.close();
    }
  }

  Future<void> _openBrowser(Uri url) async {
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Fällt unten auf den Fehler-Zweig: Die URL wird angezeigt,
      // damit sie von Hand geöffnet werden kann.
    }
    if (!opened && mounted) setState(() => _error = url.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MSheetScaffold<_SignInResult>(
      title: l10n.sync.onedriveSignIn,
      icon: LucideIcons.keyRound,
      actions: [
        MAction(label: l10n.common.cancel, value: null),
      ],
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 14,
        children: [
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
