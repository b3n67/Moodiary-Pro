import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_sync/src/data/onedrive_auth.dart';
import 'package:moodiary_sync/src/data/onedrive_http.dart';

/// Echter Loopback-HTTP-Server als Ersatz für den Microsoft-Token-Endpunkt.
class _TokenStub {
  _TokenStub(this.answer);

  final Map<String, dynamic> Function(Map<String, String> fields) answer;

  late final HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      final fields = Uri.splitQueryString(body);
      final answer = this.answer(fields);
      final status = answer.remove('__status') as int? ?? 200;
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(answer));
      await request.response.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  group('PKCE', () {
    test('challenge entspricht RFC-7636-Vektor', () {
      expect(
        OneDriveAuth.codeChallenge(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifier hat gültiges Format', () {
      final v = OneDriveAuth.newCodeVerifier();
      expect(v.length, greaterThanOrEqualTo(43));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
    });
  });

  group('authorizationUrl', () {
    test('enthält alle Loopback-Parameter', () {
      final url = OneDriveAuth.authorizationUrl(
        clientId: 'cid',
        redirectUri: 'http://localhost:1234/callback',
        state: 's',
        codeChallenge: 'c',
      );
      expect(url.host, 'login.microsoftonline.com');
      expect(
        url.queryParameters,
        containsPair('client_id', 'cid'),
        reason: 'client_id fehlt',
      );
      expect(url.queryParameters['response_type'], 'code');
      expect(
        url.queryParameters['redirect_uri'],
        'http://localhost:1234/callback',
      );
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['state'], 's');
    });
  });

  group('parseCallbackCode', () {
    test('liefert den Code bei passendem state', () {
      expect(
        OneDriveAuth.parseCallbackCode(
          Uri.parse('http://localhost:1/callback?code=abc&state=s'),
          's',
        ),
        'abc',
      );
    });

    test('wirft bei state-Mismatch', () {
      expect(
        () => OneDriveAuth.parseCallbackCode(
          Uri.parse('http://localhost:1/callback?code=abc&state=x'),
          's',
        ),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('reicht Microsoft-Fehler durch', () {
      expect(
        () => OneDriveAuth.parseCallbackCode(
          Uri.parse(
            'http://localhost:1/callback?error=access_denied&state=s',
          ),
          's',
        ),
        throwsA(isA<OneDriveAuthException>()),
      );
    });
  });

  group('OneDriveHttp', () {
    test('POST-Form und Antwort-Bytes kommen durch', () async {
      Map<String, String>? seen;
      final stub = _TokenStub((fields) {
        seen = fields;
        return {'ok': true};
      });
      await stub.start();
      try {
        final http = OneDriveHttp();
        final response = await http.postForm(
          Uri.parse('http://localhost:${stub.server.port}/token'),
          {'grant_type': 'x', 'code': 'y z'},
        );
        expect(response.statusCode, 200);
        expect(jsonDecode(utf8.decode(response.body)), {'ok': true});
        expect(seen?['grant_type'], 'x');
        expect(seen?['code'], 'y z');
      } finally {
        await stub.stop();
      }
    });

    test('unerreichbarer Host wirft typisierte Exception', () async {
      final http = OneDriveHttp();
      try {
        await http.postForm(
          Uri.parse('http://127.0.0.1:1/token'),
          {'a': 'b'},
          timeout: const Duration(seconds: 5),
        );
        fail('muss werfen');
      } on OneDriveHttpException catch (e) {
        expect(e.statusCode, isNull);
        expect(e.message, isNotEmpty);
      }
    });

    test('isDnsFailure erkennt Namensauflösungsfehler', () {
      expect(
        const OneDriveHttpException('Failed host lookup: x').isDnsFailure,
        isTrue,
      );
      expect(const OneDriveHttpException('reset by peer').isDnsFailure, isFalse);
    });
  });

  group('refresh', () {
    test('nutzt grant_type=refresh_token und parst Antwort', () async {
      Map<String, String>? seen;
      final stub = _TokenStub((fields) {
        seen = fields;
        return {
          'access_token': 'a',
          'refresh_token': 'r',
          'expires_in': 3600,
        };
      });
      await stub.start();
      final auth = OneDriveAuth(
        null,
        'http://localhost:${stub.server.port}',
      );
      addTearDown(auth.close);
      try {
        final token = await auth.refresh('cid', 'old');
        expect(token.accessToken, 'a');
        expect(token.refreshToken, 'r');
        expect(seen?['grant_type'], 'refresh_token');
        expect(seen?['refresh_token'], 'old');
      } finally {
        await stub.stop();
      }
    });

    test('wirft bei Fehlerantwort', () async {
      final stub = _TokenStub(
        (fields) => {'error': 'invalid_grant', '__status': 400},
      );
      await stub.start();
      final auth = OneDriveAuth(
        null,
        'http://localhost:${stub.server.port}',
      );
      addTearDown(auth.close);
      try {
        expect(
          auth.refresh('cid', 'bad'),
          throwsA(isA<OneDriveAuthException>()),
        );
      } finally {
        await stub.stop();
      }
    });
  });
}
