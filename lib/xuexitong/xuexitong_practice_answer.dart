/// 学习通随堂练习页面在服务端渲染学生答案后，会执行
/// `this.isAnswered = "1";`。只认这个标记，找不到时按未提交处理。
bool parseXuexitongPracticeAnswered(String html) {
  return RegExp(r'''isAnswered\s*=\s*["']1["']''').hasMatch(html);
}
