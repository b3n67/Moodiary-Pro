library;

import 'dart:async';
import 'dart:convert';

import 'package:moodiary_http/moodiary_http.dart';

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

/// State of an OAuth 2.0 device authorization flow (RFC 8628).
class OneDriveDeviceFlow {
  const OneDriveDeviceFlow({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresAt,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration interval;
  final DateTime expiresAt;
}

class OneDriveAuthException implements Exception {
  const OneDriveAuthException(this.message);

  final String message;

  @override
  String toString() => 'OneDriveAuthException: $message';
}

/// OAuth 2.0 device authorization grant against the Microsoft identity
/// platform v2.0 endpoint. Works with work/school and personal accounts,
/// needs no app secret and no browser custom-tab integration.
class OneDriveAuth {
  OneDriveAuth(this._http);

  static const _authority = 'https://login.microsoftonline.com/common';
  static const _scope = 'Files.ReadWrite.All offline_access';

  static const _authorizationPending = 'authorization_pending';
  static const _slowDown = 'slow_down';
  static const _expiredToken = 'expired_token';
  static const _authorizationDeclined = 'authorization_declined';

  final IHttpClient _http;

  Future<OneDriveDeviceFlow> startDeviceFlow(String clientId) async {
    final response = await _post(
      '$_authority/oauth2/v2.0/devicecode',
      {
        'client_id': clientId,
        'scope': _scope,
      },
    );
    final data = _requireObject(response, 'device code request failed');
    final deviceCode = data['device_code'];
    final userCode = data['user_code'];
    final verificationUri = data['verification_uri'];
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        verificationUri is! String ||
        verificationUri.isEmpty) {
      throw OneDriveAuthException(_errorDetail(response) ?? 'bad response');
    }
    return OneDriveDeviceFlow(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      interval: Duration(
        seconds: (data['interval'] as num?)?.toInt() ?? 5,
      ),
      expiresAt: DateTime.now().add(
        Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 900),
      ),
    );
  }

  /// Polls the token endpoint until the user completes or denies sign-in.
  /// [onStatus] receives human readable progress messages.
  Future<OneDriveToken> pollForToken(
    String clientId,
    OneDriveDeviceFlow flow, {
    void Function(String message)? onStatus,
  }) async {
    final stopwatch = Stopwatch()..start();
    var interval = flow.interval;
    while (true) {
      if (DateTime.now().isAfter(flow.expiresAt)) {
        throw OneDriveAuthException('The sign-in window expired');
      }
      final response = await _post(
        '$_authority/oauth2/v2.0/token',
        {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': flow.deviceCode,
          'client_id': clientId,
        },
      );
      if (response.statusCode == 200) {
        final token = _tokenFromResponse(response);
        onStatus?.call('Signed in');
        return token;
      }
      final error = _errorField(response);
      switch (error) {
        case _authorizationPending:
          onStatus?.call('Waiting for you to finish signing in…');
        case _slowDown:
          interval += const Duration(seconds: 5);
          onStatus?.call('Waiting for you to finish signing in…');
        case _authorizationDeclined:
          throw OneDriveAuthException('You declined the sign-in request');
        case _expiredToken:
          throw OneDriveAuthException('The sign-in window expired');
        default:
          throw OneDriveAuthException(
            _errorDetail(response) ?? 'sign-in failed',
          );
      }
      await Future<void>.delayed(interval);
      if (stopwatch.elapsed.inMinutes >= 15) {
        throw OneDriveAuthException('The sign-in took too long');
      }
    }
  }

  Future<OneDriveToken> refresh(String clientId, String refreshToken) async {
    final response = await _post(
      '$_authority/oauth2/v2.0/token',
      {
        'grant_type': 'refresh_code',
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

  OneDriveToken _tokenFromResponse(HttpResponse<Uint8List> response) {
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

  Future<HttpResponse<Uint8List>> _post(
    String url,
    Map<String, dynamic> fields,
  ) async {
    return _http.requestBytes(
      HttpMethod.post,
      url,
      body: HttpBody.form(fields),
      silent: true,
      throwOnStatus: false,
      timeout: const Duration(seconds: 30),
    );
  }

  Map<String, dynamic> _decode(HttpResponse<Uint8List> response) {
    final data = response.data;
    if (data == null || data.isEmpty) return const {};
    try {
      final decoded = jsonDecode(utf8.decode(data));
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> _requireObject(
    HttpResponse<Uint8List> response,
    String message,
  ) {
    if (response.statusCode != 200) {
      throw OneDriveAuthException(
        _errorDetail(response) ?? message,
      );
    }
    return _decode(response);
  }

  String? _errorField(HttpResponse<Uint8List> response) {
    final error = _decode(response)['error'];
    return error is String ? error : null;
  }

  String? _errorDetail(HttpResponse<Uint8List> response) {
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
