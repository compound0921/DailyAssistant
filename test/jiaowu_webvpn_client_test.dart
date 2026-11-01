import 'dart:convert';
import 'dart:typed_data';

import 'package:daily_assistant/jiaowu/jiaowu_webvpn_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_null.dart';
import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';

void main() {
  test('recognizes and submits the new CAS RSA login form', () async {
    final adapter = _CasAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = JiaowuWebvpnClient(dio: dio);

    await client.login(account: '20260001', password: 'secret');

    final submitted = adapter.submittedForm;
    expect(submitted?['username'], '20260001');
    expect(submitted?['password'], startsWith('__RSA__'));
    expect(submitted?['password'], isNot(contains('secret')));
    expect(submitted?['execution'], 'test-execution');
    expect(submitted?['_eventId'], 'submit');
    expect(adapter.loginPostUri?.queryParameters['service'], isNotEmpty);
  });

  test('continues to recognize the legacy login page', () {
    expect(
      JiaowuWebvpnClient.isLoginPage(
        '<form id="loginForm"><input id="lt"></form>',
      ),
      isTrue,
    );
  });
}

class _CasAdapter implements HttpClientAdapter {
  Map<String, dynamic>? submittedForm;
  Uri? loginPostUri;

  static final String publicKey = _testPublicKey();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    if (uri.path.endsWith('/jwt/publicKey')) {
      return ResponseBody.fromString(publicKey, 200);
    }
    if (uri.path.endsWith('/cas/login')) {
      if (options.method == 'POST') {
        loginPostUri = uri;
        submittedForm = Map<String, dynamic>.from(options.data as Map);
        return ResponseBody.fromString('<html><title>登录成功</title></html>', 200);
      }
      return ResponseBody.fromString(_casPage, 200);
    }
    if (uri.path.contains('index_cxDbsy.html')) {
      return ResponseBody.fromString('<table id="tabGrid1"></table>', 200);
    }
    if (uri.path.contains('kscx_cxXsksxxIndex.html')) {
      return ResponseBody.fromString('<table id="tabGrid"></table>', 200);
    }
    if (uri.path == '/login') {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [
            '/https/test-cas/cas/login?service=https%3A%2F%2Fwvpn.qust.edu.cn%2Flogin%3Fcas_login%3Dtrue',
          ],
        },
      );
    }
    return ResponseBody.fromString('<html><title>ok</title></html>', 200);
  }

  @override
  void close({bool force = false}) {}
}

const _casPage = '''
<form method="post" id="fm1" action="login">
  <input type="hidden" name="username" value="">
  <input type="hidden" name="password" value="">
  <input type="hidden" name="execution" value="test-execution">
  <input type="hidden" name="_eventId" value="submit">
  <input type="hidden" name="geolocation" value="">
</form>
''';

String _testPublicKey() {
  final modulus = BigInt.parse(
    'c7a3f25d474fd412c72032d8e42af8f13c988b334b41a7955a5149b0760c0ec1'
    'ac77d5cd30bab03e96d4b6a610cbe00486d474f949ad47b1e1363b8244bc7aba'
    '7396769c74e5e3d2a9b62fa5f1bd390ee7408c5d901e48a12348f171233dd686'
    '0eae51008dbf5e31fd7b562c497d6b1d3d653cfd28f465e17a4fc25346fe48d7',
    radix: 16,
  );
  final rsaKey = ASN1Sequence()
    ..add(ASN1Integer(modulus))
    ..add(ASN1Integer(BigInt.from(65537)));
  final algorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]))
    ..add(ASN1Null());
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(algorithm)
    ..add(ASN1BitString(stringValues: rsaKey.encode()));
  final encoded = base64Encode(subjectPublicKeyInfo.encode());
  return '-----BEGIN PUBLIC KEY-----\n$encoded\n-----END PUBLIC KEY-----';
}
