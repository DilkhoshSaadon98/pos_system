import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Password storage for the local login.
///
/// Salted SHA-256 with a stretched loop. This is a single-shop offline app, not
/// a public web service — the threat is somebody opening the .db file with a
/// SQLite browser, and a per-user salt plus stretching answers that. It is
/// deliberately not plain text, which is what the old app stored.
class Security {
  const Security._();

  static const int _rounds = 20000;
  static final Random _random = Random.secure();

  static String newSalt([int bytes = 16]) {
    final List<int> raw =
        List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(raw);
  }

  static String hashPassword(String password, String salt) {
    List<int> digest = utf8.encode('$salt::$password');
    for (int i = 0; i < _rounds; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Url.encode(digest);
  }

  static bool verifyPassword(String password, String salt, String expected) {
    final String actual = hashPassword(password, salt);
    // Constant-time-ish comparison; lengths are equal for the same algorithm.
    if (actual.length != expected.length) return false;
    int diff = 0;
    for (int i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }
}
