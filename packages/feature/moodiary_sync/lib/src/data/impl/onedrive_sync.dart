library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_sync/src/data/model/sync_provider.dart';
import 'package:moodiary_sync/src/data/onedrive_auth.dart';
import 'package:moodiary_sync/src/data/remote_lease.dart';
import 'package:moodiary_sync/src/data/secure_options.dart';
import 'package:moodiary_sync/src/data/sync.dart';
import 'package:moodiary_sync/src/data/sync_key_manager.dart';

// 配置索引：0 clientId、1 accessToken、2 refreshToken、3 token 过期时间戳（毫秒）。
@Named(SyncProviderIds.onedrive)
@LazySingleton(as: IRemoteSyncBackend)
class OneDriveSyncBackend implements IRemoteSyncBackend {
  OneDriveSyncBackend(@Named(SyncProviderIds.onedrive) this._config);

  static const _graph = 'https://graph.microsoft.com/v1.0';

  final SecureOptions _config;

  IHttpClient? _http;
  Future<List<String>>? _options;
  OneDriveToken? _token;
  Future<void>? _refreshing;

  Future<List<String>> _read() => _options ??= _config.read();

  static String _at(List<String> o, int i) => o.length > i ? o[i] : '';

  static bool _ready(List<String> o) =>
      _at(o, 0).isNotEmpty && _at(o, 1).isNotEmpty && _at(o, 2).isNotEmpty;

  IHttpClient get http => _http ??= RustHttpClient();

  OneDriveAuth get auth => OneDriveAuth(http);

  @override
  SyncProviderType get type => .onedrive;

  @override
  String get persistentBackendId => SyncProviderType.onedrive.value;

  @override
  String get displayName => type.label;

  @override
  Future<bool> isReady() async => _ready(await _read());

  Future<OneDriveToken> _loadToken() async {
    if (_token != null) return _token!;
    final opts = await _read();
    final expiryMillis = int.tryParse(_at(opts, 3));
    if (expiryMillis == null) {
      throw SyncException(
        l10n.sync.onedriveNotSignedIn,
        kind: .notConfigured,
      );
    }
    _token = OneDriveToken(
      accessToken: _at(opts, 1),
      refreshToken: _at(opts, 2),
      expiry: DateTime.fromMillisecondsSinceEpoch(expiryMillis),
    );
    return _token!;
  }

  /// Returns a valid access token, refreshing it when it is about to
  /// expire. Concurrent callers share one refresh round-trip.
  Future<OneDriveToken> _ensureToken() async {
    var token = await _loadToken();
    if (!token.isExpiringSoon) return token;
    final pending = _refreshing;
    if (pending != null) {
      await pending;
      return _loadToken();
    }
    final future = _refreshToken().then((_) async {
      final refreshed = await _loadToken();
      return refreshed;
    });
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _refreshToken() async {
    final opts = await _read();
    final clientId = _at(opts, 0);
    final old = await _loadToken();
    final token = await auth.refresh(clientId, old.refreshToken);
    _token = token;
    await _config.save([
      clientId,
      token.accessToken,
      token.refreshToken,
      '${token.expiry.millisecondsSinceEpoch}',
    ]);
    _options = null;
  }

  Future<HttpResponse<Uint8List>> _request(
    HttpMethod method,
    String url, {
    Map<String, dynamic>? headers,
    HttpBody? body,
    Duration? timeout,
  }) async {
    final token = await _ensureToken();
    final response = await http.requestBytes(
      method,
      url,
      headers: {
        'authorization': 'Bearer ${token.accessToken}',
        ...?headers,
      },
      body: body,
      silent: true,
      throwOnStatus: false,
      timeout: timeout,
    );
    if (response.statusCode == 401) {
      // The token may have been revoked server-side; refresh once and retry.
      _token = null;
      final retry = await _ensureToken();
      return http.requestBytes(
        method,
        url,
        headers: {
          'authorization': 'Bearer ${retry.accessToken}',
          ...?headers,
        },
        body: body,
        silent: true,
        throwOnStatus: false,
        timeout: timeout,
      );
    }
    return response;
  }

  String _itemUrl(String key, {bool content = false}) {
    final path = key
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return '$_graph/me/drive/root:/$path:${content ? '/content' : ''}';
  }

  @override
  Future<void> testConnection() async {
    if (!await isReady()) throw notReadyError;
    try {
      final response = await _request(HttpMethod.get, '$_graph/me/drive/root');
      if (response.statusCode != 200) {
        throw SyncException(
          l10n.sync.connectFailed(
            error: l10n.sync.onedriveDriveError,
          ),
          kind: .http,
        );
      }
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException.wrap(e, (d) => l10n.sync.connectFailed(error: d));
    }
  }

  @override
  Future<Uint8List?> readObject(String key) async {
    try {
      final response = await _request(
        HttpMethod.get,
        _itemUrl(key, content: true),
        timeout: const Duration(minutes: 5),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200 || response.data == null) {
        throw _graphError(key, response, 'read');
      }
      return response.data;
    } catch (e) {
      throw _wrap(e, key, 'read');
    }
  }

  @override
  Future<void> writeObject(String key, Uint8List bytes) async {
    try {
      final response = await _request(
        HttpMethod.put,
        _itemUrl(key, content: true),
        headers: {'content-type': 'application/octet-stream'},
        body: HttpBody.raw(bytes),
        timeout: const Duration(minutes: 10),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw _graphError(key, response, 'write');
      }
    } catch (e) {
      throw _wrap(e, key, 'write');
    }
  }

  @override
  bool get supportsFileObjects => true;

  @override
  Future<bool> readObjectToFile(String key, String filePath) async {
    try {
      final bytes = await readObject(key);
      if (bytes == null) return false;
      await File(filePath).writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      throw _wrap(e, key, 'read');
    }
  }

  @override
  Future<void> writeObjectFile(String key, String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      await writeObject(key, bytes);
    } catch (e) {
      throw _wrap(e, key, 'write');
    }
  }

  @override
  Future<ExclusiveCreate> tryCreateExclusive(String key, Uint8List bytes) async {
    try {
      // Graph has no documented conditional create for /content uploads, so
      // check existence first and keep the If-None-Match hint as a safety net.
      final stat = await statObject(key);
      if (stat != null) return .exists;
      final response = await _request(
        HttpMethod.put,
        _itemUrl(key, content: true),
        headers: {
          'content-type': 'application/octet-stream',
          'if-none-match': '*',
        },
        body: HttpBody.raw(bytes),
        timeout: const Duration(minutes: 10),
      );
      return switch (response.statusCode) {
        200 || 201 => .created,
        412 => .exists,
        400 || 405 || 501 => .unsupported,
        _ => .unsupported,
      };
    } catch (e) {
      throw _wrap(e, key, 'create');
    }
  }

  @override
  Future<void> deleteObject(String key) async {
    try {
      final response = await _request(
        HttpMethod.delete,
        _itemUrl(key),
        timeout: const Duration(minutes: 2),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        throw _graphError(key, response, 'delete');
      }
    } catch (e) {
      throw _wrap(e, key, 'delete');
    }
  }

  @override
  Future<String?> statObject(String key) async {
    try {
      final response = await _request(
        HttpMethod.get,
        _itemUrl(key),
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200 || response.data == null) {
        throw _graphError(key, response, 'stat');
      }
      final decoded = jsonDecode(utf8.decode(response.data!));
      if (decoded is! Map<String, dynamic>) return null;
      final etag = decoded['eTag'];
      final modified = decoded['lastModifiedDateTime'];
      final stamp = etag is String && etag.isNotEmpty
          ? etag
          : modified is String && modified.isNotEmpty
              ? modified
              : '';
      return stamp.isEmpty ? null : stamp;
    } catch (e) {
      throw _wrap(e, key, 'stat');
    }
  }

  SyncException _graphError(String key, HttpResponse<Uint8List> response, String action) {
    final detail = _errorDetail(response);
    return SyncException(
      detail != null
          ? l10n.sync.errStatRemote(key: key, error: detail)
          : l10n.sync.errStatRemote(key: key, error: 'HTTP ${response.statusCode}'),
      kind: _kind(response.statusCode),
    );
  }

  SyncErrorKind _kind(int? status) => switch (status) {
        401 || 403 => .auth,
        404 => .notFound,
        final int s when s >= 500 => .server,
        _ => .http,
      };

  String? _errorDetail(HttpResponse<Uint8List> response) {
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Object _wrap(Object e, String key, String action) {
    if (e is SyncException) return e;
    if (e is OneDriveAuthException) {
      return SyncException(
        l10n.sync.onedriveAuthFailed(error: e.message),
        kind: .auth,
      );
    }
    if (e is HttpException) {
      return SyncException(
        l10n.sync.errReadRemote(key: key, error: e.message),
        kind: switch (e.type) {
          HttpErrorType.timeout || HttpErrorType.connection => .network,
          HttpErrorType.statusCode => _kind(e.statusCode),
          _ => .http,
        },
      );
    }
    return SyncException(
      l10n.sync.errReadRemote(key: key, error: e.toString()),
      kind: .unknown,
    );
  }

  @override
  SyncException get notReadyError =>
      SyncException(l10n.sync.errOnedriveConfig, kind: .notConfigured);

  @override
  Future<List<String>> savedOptions() => _read();

  @override
  Future<void> saveOptions(List<String> options) async {
    await _config.save(options);
    _options = null;
    _token = null;
    RemoteLease.resetCasProbeCache();
    if (await SyncKeyManager.loadDek() != null) {
      await SyncKeyManager.markPendingUpload([type.value]);
    }
  }

  @override
  Future<void> clearOptions() async {
    await _config.clear();
    _options = null;
    _token = null;
    RemoteLease.resetCasProbeCache();
  }
}
