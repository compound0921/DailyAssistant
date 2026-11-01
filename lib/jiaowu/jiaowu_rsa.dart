import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1/asn1_object.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';

/// 使用 CAS 登录页公开的 RSA 公钥进行 PKCS#1 v1.5 加密。
///
/// 新版登录页通过 JSEncrypt 生成 Base64 密文，并在提交值前加 `__RSA__`。
String encryptCasPassword(String password, String publicKeyPem) {
  final key = _parsePublicKey(publicKeyPem);
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(key));
  final plain = Uint8List.fromList(utf8.encode(password));
  if (plain.length > cipher.inputBlockSize) {
    throw const FormatException('密码长度超过 CAS RSA 公钥允许的范围');
  }
  return base64Encode(cipher.process(plain));
}

RSAPublicKey _parsePublicKey(String pem) {
  final normalized = pem
      .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
      .replaceAll(RegExp(r'-----END [^-]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (normalized.isEmpty) {
    throw const FormatException('CAS RSA 公钥为空');
  }

  final root = ASN1Parser(base64Decode(normalized)).nextObject();
  if (root is! ASN1Sequence) {
    throw const FormatException('无法解析 CAS RSA 公钥');
  }

  // SubjectPublicKeyInfo: SEQUENCE(algorithm, BIT STRING(RSAPublicKey)).
  if (root.elements?.length == 2 && root.elements![1] is ASN1BitString) {
    final bits = root.elements![1] as ASN1BitString;
    final inner = ASN1Parser(
      Uint8List.fromList(bits.stringValues!),
    ).nextObject();
    return _rsaKeyFromSequence(inner);
  }

  // 同时兼容 PKCS#1 的 `BEGIN RSA PUBLIC KEY`。
  return _rsaKeyFromSequence(root);
}

RSAPublicKey _rsaKeyFromSequence(ASN1Object object) {
  if (object is! ASN1Sequence ||
      object.elements == null ||
      object.elements!.length < 2 ||
      object.elements![0] is! ASN1Integer ||
      object.elements![1] is! ASN1Integer) {
    throw const FormatException('CAS RSA 公钥结构无效');
  }
  final modulus = (object.elements![0] as ASN1Integer).integer;
  final exponent = (object.elements![1] as ASN1Integer).integer;
  if (modulus == null || exponent == null) {
    throw const FormatException('CAS RSA 公钥参数缺失');
  }
  return RSAPublicKey(modulus, exponent);
}
