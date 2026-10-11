library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class OneDriveHttpException implements Exception {
  const OneDriveHttpException(this.message, {this.statusCode, this.osError});

  final String message;
  final int? statusCode;
  final String? osError;

  /// True bei fehlgeschlagener Namensauflösung (geräteseitiges DNS-Problem:
  /// Privates DNS, VPN oder DNS-/Werbeblocker-App).
  bool get isDnsFailure =>
      message.contains('Failed host lookup') ||
      (osError?.contains('No address associated') ?? false);

  @override
  String toString() =>
      'OneDriveHttpException(${statusCode ?? '?'}): $message';
}

class OneDriveHttpResponse {
  const OneDriveHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Uint8List body;
}

/// Minimaler HTTP-Client auf dart:io-Basis (System-TLS) für OneDrive.
/// Der Rust-Client scheiterte auf manchen Geräten/Netzen bereits am
/// Token-Endpunkt mit Verbindungsfehlern, während der Browser ging.
class OneDriveHttp {
  OneDriveHttp({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<OneDriveHttpResponse> request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Uint8List? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Einmal wiederholen: kurze Funklöcher beim Wechsel WLAN/mobil heilen so.
    // Alles (inkl. Body-Empfang) läuft im Timeout, nichts hängt ewig.
    SocketException? failed;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      try {
        return await _requestOnce(
          method,
          url,
          headers: headers,
          body: body,
        ).timeout(timeout);
      } on SocketException catch (e) {
        failed = e;
      }
    }
    throw OneDriveHttpException(
      failed?.message ?? 'connection failed',
      osError: failed?.osError?.message,
    );
  }

  Future<OneDriveHttpResponse> _requestOnce(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Uint8List? body,
  }) async {
    final req = await _client.openUrl(method, url);
    headers?.forEach(req.headers.set);
    if (body != null) req.add(body);
    final resp = await req.close();
    final bytes = await resp.fold<BytesBuilder>(
      BytesBuilder(),
      (b, d) => b..add(d),
    ).then((b) => b.takeBytes());
    return OneDriveHttpResponse(resp.statusCode, bytes);
  }

  Future<OneDriveHttpResponse> postForm(
    Uri url,
    Map<String, String> fields, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final encoded = fields.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return request(
      'POST',
      url,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: Uint8List.fromList(utf8.encode(encoded)),
      timeout: timeout,
    );
  }
}
