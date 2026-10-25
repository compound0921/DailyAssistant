import 'dart:convert';

import 'package:crypto/crypto.dart';

/// `inf_enc` query signing used by the read-only student data endpoints.
///
/// This is a trimmed copy of the upstream `ChaoxingSignCrypto`. Device RSA,
/// `cxsign`, `webRequestSign`, and the embedded private key are removed; only
/// the scheme needed by `ChaoxingApiService` remains.
class ChaoxingSignCrypto {
  const ChaoxingSignCrypto._();

  /// `bw/C3031h.f3839a`, `u00/C37376y.f144088a` — the app-wide inf_enc token.
  static const infEncToken = '4faa8662c59590c6f43ae9fe5b002b42';

  /// `u00/C37376y.m155194B` / `bw/C3030g` ctor arg — the inf_enc DES key.
  static const infEncDesKey = 'Z(AfY@XS';

  /// Lowercase hex MD5 of [input] (UTF-8).
  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  /// `URLEncoder.encode(v, "UTF-8").replaceAll("\\+", "%20")`.
  static String javaUrlEncode(String value) => Uri.encodeQueryComponent(
    value,
    encoding: utf8,
  ).replaceAll('+', '%20').replaceAll('%2A', '*').replaceAll('~', '%7E');

  /// `jui.R` — the pre-image of `inf_enc`, in declared parameter order.
  static String infEncBase(
    List<String> names,
    List<String?> values, {
    required int timeMillis,
    String token = infEncToken,
  }) {
    if (names.length != values.length) {
      throw ArgumentError('names and values must have equal length');
    }
    final sb = StringBuffer()
      ..write('token=')
      ..write(token)
      ..write('&_time=')
      ..write(timeMillis);
    for (var i = 0; i < names.length; i++) {
      final v = values[i];
      if (v == null) continue;
      sb
        ..write('&')
        ..write(names[i])
        ..write('=')
        ..write(javaUrlEncode(v));
    }
    return sb.toString();
  }

  /// `jui.E` — appends `&inf_enc=MD5(base + "&DESKey=" + key)` to [base].
  static String infEnc(String base, {String desKey = infEncDesKey}) =>
      '$base&inf_enc=${md5Hex('$base&DESKey=$desKey')}';

  /// `jui.V` / `jui.W` — the full signed query string.
  static String signedQuery(
    List<String> names,
    List<String?> values, {
    required int timeMillis,
    String token = infEncToken,
    String desKey = infEncDesKey,
  }) => infEnc(
    infEncBase(names, values, timeMillis: timeMillis, token: token),
    desKey: desKey,
  );
}
