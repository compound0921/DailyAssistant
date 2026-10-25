import 'package:daily_assistant/jiaowu/jiaowu_des.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 期望值由正方登录页同款 des.js（strEnc(data, '1', '2', '3')）生成。
  test('matches the upstream DES login encryption', () {
    expect(jiaowuEncryptLogin('a'), 'A62B4F77D5F8C6C7');
    expect(
      jiaowuEncryptLogin('测试1234'),
      '7DFBF89ACA3584514C035B42B543AD35',
    );
    expect(
      jiaowuEncryptLogin('admin123LT-123456-abc-tpass'),
      '012C2C9BA925FAF8F8D702931DB661E93F87C346C8672F7C50B87714D462E933'
      '3D08059BB00BA2EE2391BE954EB337999668FE464C1DBD45',
    );
  });

  test('empty input stays empty', () {
    expect(jiaowuEncryptLogin(''), '');
  });
}
