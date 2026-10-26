import 'package:daily_assistant/xuexitong/xuexitong_practice_answer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('识别随堂练习页面里的已提交标记', () {
    expect(parseXuexitongPracticeAnswered('this.isAnswered = "1";'), isTrue);
    expect(parseXuexitongPracticeAnswered("this.isAnswered = '1';"), isTrue);
    expect(
      parseXuexitongPracticeAnswered('this.isAnswered   =   "1";'),
      isTrue,
    );
  });

  test('未提交或缺少标记时返回 false', () {
    expect(parseXuexitongPracticeAnswered('this.isAnswered = "0";'), isFalse);
    expect(parseXuexitongPracticeAnswered("isAnswered: '0'"), isFalse);
    expect(parseXuexitongPracticeAnswered('<html></html>'), isFalse);
  });
}
