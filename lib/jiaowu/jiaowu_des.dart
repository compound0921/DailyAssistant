/// 复刻正方统一身份认证登录页 `des.js` 的 `strEnc(data, '1', '2', '3')`。
///
/// 这不是标准 DES 库的直接替代：`des.js` 的密钥位序与标准实现不同，
/// 必须按它的位数组和排列表原样移植，才能和服务端解出同一串。
String jiaowuEncryptLogin(String data) {
  if (data.isEmpty) return '';

  final codeUnits = data.codeUnits;
  final output = StringBuffer();

  for (var start = 0; start < codeUnits.length; start += 4) {
    final dataBits = List<int>.filled(64, 0);
    for (var offset = 0; offset < 4; offset++) {
      final index = start + offset;
      final codeUnit = index < codeUnits.length ? codeUnits[index] : 0;
      for (var bit = 0; bit < 16; bit++) {
        dataBits[16 * offset + bit] = (codeUnit >> (15 - bit)) & 1;
      }
    }

    var encrypted = _encryptBlock(dataBits, _keyBits(0x31)); // '1'
    encrypted = _encryptBlock(encrypted, _keyBits(0x32)); // '2'
    encrypted = _encryptBlock(encrypted, _keyBits(0x33)); // '3'

    for (var index = 0; index < 64; index += 4) {
      final nibble =
          encrypted[index] * 8 +
          encrypted[index + 1] * 4 +
          encrypted[index + 2] * 2 +
          encrypted[index + 3];
      output.write(nibble.toRadixString(16).toUpperCase());
    }
  }

  return output.toString();
}

List<int> _keyBits(int codeUnit) {
  final bits = List<int>.filled(64, 0);
  for (var bit = 0; bit < 16; bit++) {
    bits[bit] = (codeUnit >> (15 - bit)) & 1;
  }
  return bits;
}

List<int> _encryptBlock(List<int> dataByte, List<int> keyByte) {
  final keys = _generateKeys(keyByte);
  final ipByte = _initPermute(dataByte);
  final ipLeft = List<int>.filled(32, 0);
  final ipRight = List<int>.filled(32, 0);
  final tempLeft = List<int>.filled(32, 0);

  for (var index = 0; index < 32; index++) {
    ipLeft[index] = ipByte[index];
    ipRight[index] = ipByte[32 + index];
  }

  for (var round = 0; round < 16; round++) {
    for (var index = 0; index < 32; index++) {
      tempLeft[index] = ipLeft[index];
      ipLeft[index] = ipRight[index];
    }
    final tempRight = _xor(
      _pPermute(_sBoxPermute(_xor(_expandPermute(ipRight), keys[round]))),
      tempLeft,
    );
    for (var index = 0; index < 32; index++) {
      ipRight[index] = tempRight[index];
    }
  }

  final finalData = List<int>.filled(64, 0);
  for (var index = 0; index < 32; index++) {
    finalData[index] = ipRight[index];
    finalData[32 + index] = ipLeft[index];
  }
  return _finallyPermute(finalData);
}

List<int> _initPermute(List<int> originalData) {
  final ipByte = List<int>.filled(64, 0);
  for (var i = 0, m = 1, n = 0; i < 4; i++, m += 2, n += 2) {
    for (var j = 7, k = 0; j >= 0; j--, k++) {
      ipByte[i * 8 + k] = originalData[j * 8 + m];
      ipByte[i * 8 + k + 32] = originalData[j * 8 + n];
    }
  }
  return ipByte;
}

List<int> _expandPermute(List<int> rightData) {
  final expanded = List<int>.filled(48, 0);
  for (var i = 0; i < 8; i++) {
    expanded[i * 6] = i == 0 ? rightData[31] : rightData[i * 4 - 1];
    expanded[i * 6 + 1] = rightData[i * 4];
    expanded[i * 6 + 2] = rightData[i * 4 + 1];
    expanded[i * 6 + 3] = rightData[i * 4 + 2];
    expanded[i * 6 + 4] = rightData[i * 4 + 3];
    expanded[i * 6 + 5] = i == 7 ? rightData[0] : rightData[i * 4 + 4];
  }
  return expanded;
}

List<int> _xor(List<int> left, List<int> right) {
  final result = List<int>.filled(left.length, 0);
  for (var index = 0; index < left.length; index++) {
    result[index] = left[index] ^ right[index];
  }
  return result;
}

List<int> _sBoxPermute(List<int> expandByte) {
  final sBoxByte = List<int>.filled(32, 0);
  for (var box = 0; box < 8; box++) {
    final row = expandByte[box * 6] * 2 + expandByte[box * 6 + 5];
    final column =
        expandByte[box * 6 + 1] * 8 +
        expandByte[box * 6 + 2] * 4 +
        expandByte[box * 6 + 3] * 2 +
        expandByte[box * 6 + 4];
    final value = _sBoxes[box][row][column];
    sBoxByte[box * 4] = (value >> 3) & 1;
    sBoxByte[box * 4 + 1] = (value >> 2) & 1;
    sBoxByte[box * 4 + 2] = (value >> 1) & 1;
    sBoxByte[box * 4 + 3] = value & 1;
  }
  return sBoxByte;
}

List<int> _pPermute(List<int> sBoxByte) {
  return [
    for (final index in _pPermuteIndexes) sBoxByte[index],
  ];
}

List<int> _finallyPermute(List<int> endByte) {
  return [
    for (final index in _finallyPermuteIndexes) endByte[index],
  ];
}

List<List<int>> _generateKeys(List<int> keyByte) {
  final key = List<int>.filled(56, 0);
  final keys = List<List<int>>.generate(
    16,
    (_) => List<int>.filled(48, 0),
  );

  for (var i = 0; i < 7; i++) {
    for (var j = 0, k = 7; j < 8; j++, k--) {
      key[i * 8 + j] = keyByte[8 * k + i];
    }
  }

  for (var round = 0; round < 16; round++) {
    for (var rotation = 0; rotation < _keyRotations[round]; rotation++) {
      final tempLeft = key[0];
      final tempRight = key[28];
      for (var index = 0; index < 27; index++) {
        key[index] = key[index + 1];
        key[28 + index] = key[29 + index];
      }
      key[27] = tempLeft;
      key[55] = tempRight;
    }
    for (var index = 0; index < 48; index++) {
      keys[round][index] = key[_pc2Indexes[index]];
    }
  }

  return keys;
}

const List<int> _keyRotations = [
  1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
];

const List<int> _pc2Indexes = [
  13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, 22, 18, 11, 3,
  25, 7, 15, 6, 26, 19, 12, 1, 40, 51, 30, 36, 46, 54, 29, 39,
  50, 44, 32, 47, 43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31,
];

const List<int> _pPermuteIndexes = [
  15, 6, 19, 20, 28, 11, 27, 16, 0, 14, 22, 25, 4, 17, 30, 9,
  1, 7, 23, 13, 31, 26, 2, 8, 18, 12, 29, 5, 21, 10, 3, 24,
];

const List<int> _finallyPermuteIndexes = [
  39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30,
  37, 5, 45, 13, 53, 21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28,
  35, 3, 43, 11, 51, 19, 59, 27, 34, 2, 42, 10, 50, 18, 58, 26,
  33, 1, 41, 9, 49, 17, 57, 25, 32, 0, 40, 8, 48, 16, 56, 24,
];

const List<List<List<int>>> _sBoxes = [
  [
    [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
    [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
    [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
    [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
  ],
  [
    [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
    [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
    [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
    [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
  ],
  [
    [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
    [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
    [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
    [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
  ],
  [
    [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
    [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
    [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
    [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
  ],
  [
    [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
    [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
    [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
    [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
  ],
  [
    [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
    [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
    [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
    [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
  ],
  [
    [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
    [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
    [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
    [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
  ],
  [
    [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
    [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
    [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
    [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
  ],
];
