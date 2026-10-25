import 'dart:convert';
import 'dart:io';

import '../models/timetable_store.dart';

/// 课表口令解析失败。
class TimetableShareException implements Exception {
  const TimetableShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 当前课表与一段可复制/粘贴的文本口令互转。
///
/// 口令包含完整课表数据，使用 gzip + base64url 压缩，**不加密**。
abstract final class TimetableShareCodec {
  static const String prefix = 'DA-TT1:';
  static const int _version = 1;

  static String encode(TimetableEntry entry) {
    final payload = jsonEncode({
      'v': _version,
      'entry': entry.toJson(),
    });
    final compressed = gzip.encode(utf8.encode(payload));
    return '$prefix${base64UrlEncode(compressed)}';
  }

  static TimetableEntry decode(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), '');
    if (!normalized.startsWith(prefix)) {
      throw const TimetableShareException(
        '这不是课表口令，请确认文本以 DA-TT1: 开头。',
      );
    }

    try {
      var encoded = normalized.substring(prefix.length);
      while (encoded.length % 4 != 0) {
        encoded += '=';
      }
      final bytes = base64Url.decode(encoded);
      final jsonText = utf8.decode(gzip.decode(bytes));
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        throw const TimetableShareException('课表口令内容格式不正确。');
      }
      final map = decoded.cast<String, dynamic>();
      if (map['v'] != _version) {
        throw const TimetableShareException('课表口令版本不受支持。');
      }
      final entry = map['entry'];
      if (entry is! Map) {
        throw const TimetableShareException('课表口令里没有课表数据。');
      }
      return TimetableEntry.fromJson(entry.cast<String, dynamic>());
    } on TimetableShareException {
      rethrow;
    } on FormatException catch (error) {
      throw TimetableShareException('课表口令损坏：${error.message}');
    } catch (error) {
      throw TimetableShareException('课表口令无法解析：$error');
    }
  }
}
