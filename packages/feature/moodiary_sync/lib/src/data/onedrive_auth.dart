library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_sync/src/data/onedrive_http.dart';

/// Credentials returned by the Microsoft token endpoint.
class OneDriveToken {
  const OneDriveToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiry;

  static const _margin = Duration(minutes: 5);

  bool get isExpiringSoon =>
      expiry.difference(DateTime.now()) <= _margin;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiryMillis': expiry.millisecondsSinceEpoch,
      };

  static OneDriveToken? fromJson(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expiryMillis = json['expiryMillis'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiryMillis is! int) {
      return null;
    }
    return OneDriveToken(
      accessToken: access,
      refreshToken: refresh,
      expiry: DateTime.fromMillisecondsSinceEpoch(expiryMillis),
    );
  }
}

/// OAuth 2.0 authorization code grant with PKCE (RFC 7636) against the
/// Microsoft identity platform v2.0 endpoint. Works with work/school and
/// personal accounts, needs no app secret and no browser custom-tab
/// integration: the system browser opens, the password is only ever typed
/// there, and the loopback redirect lands back in the app.
class OneDriveAuthException implements Exception {
  const OneDriveAuthException(this.message);

  final String message;

  @override
  String toString() => 'OneDriveAuthException: $message';
}

class OneDriveAuth {
  OneDriveAuth([OneDriveHttp? http, String? authority])
    : _http = http ?? OneDriveHttp(),
      _authority = authority ?? _defaultAuthority;

  /// Azure-App für OneDrive (öffentlicher Client, kein Secret).
  /// Per Build gesetzt: `--dart-define=ONEDRIVE_CLIENT_ID=<id>`.
  /// Leer im öffentlichen Code — dann trägt jede Nutzerin die eigene ID ein.
  static const defaultClientId = String.fromEnvironment(
    'ONEDRIVE_CLIENT_ID',
    defaultValue: '',
  );

  /// Fester Loopback-Redirect (exakt so in der Azure-App unter
  /// „Mobile und Desktopanwendungen" zu registrieren): Zufalls-Ports lehnt
  /// Microsoft mit invalid_request ab.
  static const loopbackRedirectUri = 'http://localhost:8080/callback';

  static const _defaultAuthority = 'https://login.microsoftonline.com/common';
  static const _scope = 'Files.ReadWrite.All offline_access';

  final OneDriveHttp _http;
  final String _authority;

  /// Gibt den zugrunde liegenden HttpClient frei (pro Sign-in eine Instanz).
  void close() => _http.close();

  Future<OneDriveToken> refresh(String clientId, String refreshToken) async {
    final response = await _post(
      '$_authority/oauth2/v2.0/token',
      {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        'scope': _scope,
      },
    );
    if (response.statusCode != 200) {
      throw OneDriveAuthException(
        _errorDetail(response) ?? 'token refresh failed',
      );
    }
    return _tokenFromResponse(response);
  }

  /// Anmeldung im System-Browser (Authorization Code + PKCE, RFC 7636):
  /// Öffnet die Microsoft-Anmeldeseite, das Konto-Passwort wird nur dort
  /// eingegeben und erreicht die App nie. Nach der Zustimmung ruft Microsoft
  /// [loopbackRedirectUri] auf diesem Gerät auf.
  /// [openUrl] öffnet die Anmelde-URL (per Default per Parameter injizierbar
  /// für Tests), [onStatus] meldet Fortschritt.
  Future<OneDriveToken> signInWithBrowser(
    String clientId, {
    Future<void> Function(Uri url)? openUrl,
    void Function(String message)? onStatus,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final verifier = newCodeVerifier();
    final state = _randomString(16);
    late final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
    } on SocketException {
      throw OneDriveAuthException(
        'Local sign-in port 8080 is busy, close the other app and retry',
      );
    }
    try {
      const redirectUri = loopbackRedirectUri;
      final authUrl = authorizationUrl(
        clientId: clientId,
        redirectUri: redirectUri,
        state: state,
        codeChallenge: codeChallenge(verifier),
      );
      onStatus?.call('Opening the Microsoft sign-in page…');
      if (openUrl != null) {
        await openUrl(authUrl);
      }
      final callback = await _waitForCallback(server, timeout);
      final code = parseCallbackCode(callback, state);
      return await _exchangeCode(
        clientId: clientId,
        redirectUri: redirectUri,
        code: code,
        verifier: verifier,
      );
    } finally {
      await server.close(force: true);
    }
  }

  /// Baut die Microsoft-Authorize-URL für den Loopback-Flow.
  @visibleForTesting
  static Uri authorizationUrl({
    required String clientId,
    required String redirectUri,
    required String state,
    required String codeChallenge,
  }) {
    return Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': _scope,
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    });
  }

  /// Erzeugt einen PKCE code_verifier (43–128 Zeichen aus unreserved set).
  @visibleForTesting
  static String newCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      64,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// S256 code_challenge aus einem Verifier (RFC 7636, ohne Padding).
  @visibleForTesting
  static String codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Prüft den Loopback-Callback: Fehler von Microsoft und state-Mismatch
  /// werden als [OneDriveAuthException] gemeldet, sonst der Code.
  @visibleForTesting
  static String parseCallbackCode(Uri callback, String state) {
    final error = callback.queryParameters['error'];
    if (error != null) {
      final description = callback.queryParameters['error_description'];
      throw OneDriveAuthException(
        description?.isNotEmpty == true ? '$error: $description' : error,
      );
    }
    if (callback.queryParameters['state'] != state) {
      throw OneDriveAuthException('sign-in reply mismatch');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw OneDriveAuthException('sign-in reply has no code');
    }
    return code;
  }

  static Future<Uri> _waitForCallback(
    HttpServer server,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw OneDriveAuthException('The sign-in took too long');
      }
      final request = await server.first.timeout(
        remaining,
        onTimeout: () =>
            throw OneDriveAuthException('The sign-in took too long'),
      );
      // Fremdanfragen (z. B. Favicon des Browsers) ignorieren.
      if (request.uri.path != '/callback') {
        try {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        } catch (_) {}
        continue;
      }
      try {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<!doctype html><html><head><meta charset="utf-8">'
            '<title>Moodiary</title></head><body>'
            '<p>Signed in. You can close this window and return to Moodiary.</p>'
            '</body></html>',
          );
        await request.response.close();
      } catch (_) {
        // Antwort ist reine Höflichkeit; der Code steht bereits in der URL.
      }
      return request.uri;
    }
  }

  Future<OneDriveToken> _exchangeCode({
    required String clientId,
    required String redirectUri,
    required String code,
    required String verifier,
  }) async {
    final response = await _post(
      '$_authority/oauth2/v2.0/token',
      {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) {
      throw OneDriveAuthException(
        _errorDetail(response) ?? 'sign-in failed',
      );
    }
    return _tokenFromResponse(response);
  }

  static String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  OneDriveToken _tokenFromResponse(OneDriveHttpResponse response) {
    final data = _decode(response);
    final access = data['access_token'];
    final refresh = data['refresh_token'];
    final expiresIn = data['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw OneDriveAuthException('bad token response');
    }
    return OneDriveToken(
      accessToken: access,
      refreshToken: refresh,
      expiry: DateTime.now().add(
        Duration(seconds: (expiresIn as num?)?.toInt() ?? 3600),
      ),
    );
  }

  Future<OneDriveHttpResponse> _post(
    String url,
    Map<String, String> fields,
  ) async {
    try {
      return await _http.postForm(Uri.parse(url), fields);
    } on TimeoutException {
      throw OneDriveAuthException('Network timeout, try again');
    } on SocketException catch (e) {
      throw OneDriveAuthException('Network error: ${e.message}');
    } on HttpException catch (e) {
      throw OneDriveAuthException('Network error: ${e.message}');
    } on OneDriveHttpException catch (e) {
      if (e.isDnsFailure) {
        throw OneDriveAuthException(l10n.sync.onedriveDnsFailed);
      }
      throw OneDriveAuthException('Network error: ${e.message}');
    }
  }

  Map<String, dynamic> _decode(OneDriveHttpResponse response) {
    final data = response.body;
    if (data.isEmpty) return const {};
    try {
      final decoded = jsonDecode(utf8.decode(data));
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  String? _errorDetail(OneDriveHttpResponse response) {
    final data = _decode(response);
    final error = data['error'];
    final description = data['error_description'];
    if (error is String && error.isNotEmpty) {
      return description is String && description.isNotEmpty
          ? '$error: $description'
          : error;
    }
    return null;
  }
}
