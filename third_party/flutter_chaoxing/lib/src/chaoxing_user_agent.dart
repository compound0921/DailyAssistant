import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Official 学习通 User-Agent construction, recovered from the 7.0.2 client.
///
/// `p482ej/C30158f.java` builds the UA in two parts:
///
/// ```java
/// // m120699c — the plaintext suffix
/// String.format(" (device:%s) %s %s/%s_%s_%s_android_phone_%s_%s (%s)_%s",
///     Build.MODEL, "Language/" + locale, packageName, "ChaoXingStudy",
///     C37365n.f144063a, versionName, versionCode, C32316b.m127070g(),
///     (m127067d() || m127065b()) ? "@Azeroth" : "@Kalimdor", uniqueId);
///
/// // m120701e — the full header
/// crypted = SecurityLib.cryptUserAgent(suffix, false);   // native transform
/// ua = sanitize(System.getProperty("http.agent") + " " + crypted);
/// ```
///
/// Every constant below was read out of the decompiled source, not guessed:
///
/// | Field | Value | Source |
/// |---|---|---|
/// | `C37365n.f144063a` | `3` | `u00/C37365n.java:9` |
/// | `C32316b.m127070g()` | `264` | `ke/C32764p.mo127072a` → `C32754f.f129562A` (`ke/C32754f.java:8`) |
/// | channel | `@Kalimdor` | `mo127076e()`/`mo127077f()` both `false` (`ke/C32764p.java:11,17`) |
/// | package | `com.chaoxing.mobile` | `C32754f.f129567b` (`ke/C32754f.java:23`) |
///
/// ## `cryptUserAgent` is an MD5, not a cipher
///
/// `libsecuritylib.so` `Java_…_cryptUserAgent` @ `0x7a9ec` wraps the suffix:
///
/// ```
/// cryptUserAgent(suffix) = "(schild:" + MD5(suffix + salt) + ")" + suffix
/// ua = http.agent + " " + cryptUserAgent(suffix)
/// ```
///
/// The salt is the 32-byte ASCII constant [uaSalt], copied into a
/// `std::string` by the `.init_array` constructor @ `0x7c29c` from `.rodata`
/// `0x53dfb`. Verified live: a header built this way is accepted by both
/// `mobilelearn` (full activity list) and `passport2-api` (`extenduserinfo`
/// returns the account), so the two-UA split below is only needed when the
/// `schild` prefix is absent.
///
/// ## Where a plaintext UA is and is not accepted (measured 2026-09-24)
///
/// The two server fleets disagree, so a headless client needs **two headers for
/// one session**:
///
/// * `passport2-api.chaoxing.com` — **rejects** it. A login carrying the
///   plaintext `ChaoXingStudy` suffix came back
///   `{"webUrl":"…/v11/tocheckmessage…","type":2,"status":true}`, i.e. risk
///   control demanding a new-device SMS second factor
///   ([ChaoxingSecondaryVerificationRequired]). The same credentials, same
///   cookies, same IP, one minute later with an ordinary mobile **browser** UA
///   came back `{"mes":"验证通过","type":1,"url":"…/apis/login/userLogin4Uname.do…"}`
///   and harvested a full SSO cookie jar. Presumably a suffix that claims to be
///   the official client but is not the crypted form reads as a spoof.
/// * `mobilelearn.chaoxing.com` — **requires** it. The same session, queried
///   with the browser UA, got
///   `{"status":0,"errorMsg":"请用学习通客户端打开活动列表"}` from
///   `ppt/activeAPI/taskactivelist`; the official UA returned all nine
///   activities.
///
/// So: log in with a browser UA, then switch to [build] for everything under
/// `mobilelearn`. Both were verified against the live service end-to-end,
/// including five classroom signs.
///
/// The fidelity win over using a browser UA everywhere is therefore real but
/// narrow — and the trailing [uniqueId] still ties the header to the same
/// device id used for registration and Fanya signs.
class ChaoxingUserAgent {
  const ChaoxingUserAgent._();

  /// `C37365n.f144063a` — protocol/build tag, constant `3` in 7.0.2.
  static const protocolTag = 3;

  /// `C32316b.m127070g()` → `C32754f.f129562A`, constant `264` in 7.0.2.
  static const screenCode = 264;

  /// Channel marker. `@Kalimdor` unless the build reports the Azeroth flags.
  static const channel = '@Kalimdor';

  /// `C32754f.f129567b` — the generic client package name.
  static const packageName = 'com.chaoxing.mobile';

  /// Salt appended before the `schild` MD5. 32 ASCII bytes, copied verbatim by
  /// the `.init_array` constructor @ `0x7c29c` from `libsecuritylib.so` `.rodata`
  /// `0x53dfb`.
  static const uaSalt = r'ipL$TkeiEmfy1gTXb2XHrdLN0a@7c^vu';

  /// The app version this UA impersonates. Keep in lock-step with the protocol
  /// constants the rest of the package targets (7.0.2).
  static const versionName = '7.0.2';

  /// `packageInfo.versionCode` for the impersonated 7.0.2 build.
  static const versionCode = '10993';

  /// The plaintext suffix (`m120699c`), i.e. everything after the Dalvik
  /// `http.agent` prefix. Begins with a single space, exactly as the native
  /// format string does.
  ///
  /// [uniqueId] is the persisted device id (`ChaoxingSignCrypto.newUniqueId`);
  /// [model] is `Build.MODEL`.
  static String plaintextSuffix({
    required String uniqueId,
    required String model,
    String locale = 'zh_CN',
    String pkg = packageName,
    String name = versionName,
    String code = versionCode,
  }) =>
      ' (device:$model) Language/$locale $pkg/ChaoXingStudy'
      '_${protocolTag}_${name}_android_phone_${code}_$screenCode'
      ' ($channel)_$uniqueId';

  /// `SecurityLib.cryptUserAgent`: wraps [suffix] with its own salted MD5.
  ///
  /// `"(schild:" + MD5(suffix + [uaSalt]) + ")" + suffix`. The digest is over the
  /// suffix exactly as [plaintextSuffix] returns it, leading space included.
  static String cryptUserAgent(String suffix) {
    final digest = md5.convert(utf8.encode(suffix + uaSalt)).toString();
    return '(schild:$digest)$suffix';
  }

  /// The full User-Agent header: the Dalvik `http.agent` prefix, the `schild`
  /// digest, then the plaintext suffix.
  ///
  /// [androidVersion] / [buildId] populate the Dalvik prefix; defaults match a
  /// generic modern Pixel. Pass the real values when impersonating a specific
  /// device so the header is internally consistent.
  static String build({
    required String uniqueId,
    String model = 'Pixel 6',
    String androidVersion = '14',
    String buildId = 'UQ1A.240205.004',
    String locale = 'zh_CN',
  }) {
    final httpAgent =
        'Dalvik/2.1.0 (Linux; U; Android $androidVersion; $model Build/$buildId)';
    final suffix = plaintextSuffix(
      uniqueId: uniqueId,
      model: model,
      locale: locale,
    );
    // http.agent + " " + cryptUserAgent(suffix). cryptUserAgent keeps the
    // suffix's leading space, so this is a single separator.
    return '$httpAgent ${cryptUserAgent(suffix)}';
  }
}
