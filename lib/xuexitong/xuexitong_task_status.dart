/// 课程页面状态；不同页面的数字编码不通用，只依据明确文字判断。
enum XuexitongTaskStatus { pending, submitted, closed, unknown }

XuexitongTaskStatus parseXuexitongTaskStatus(String text) {
  final value = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (value == '完成' || value == '提交' || value == '待批阅') {
    return XuexitongTaskStatus.submitted;
  }
  // 否定词必须先于“完成 / 提交”等肯定词。
  if (RegExp(
    r'未完成|未提交|未作答|未开始|待提交|待完成|待做|做作业|去完成|做考试|'
    r'\b(uncommitted|unsubmitted|incomplete|not submitted|not completed|not started|pending)\b',
  ).hasMatch(value)) {
    return XuexitongTaskStatus.pending;
  }
  if (RegExp(
    r'已完成|已提交|已批|已评分|已作答|待批|待评|(?:^|\s)完成(?:$|\s)|'
    r'\b(completed|submitted|graded|to be marked|awaiting grading)\b',
  ).hasMatch(value)) {
    return XuexitongTaskStatus.submitted;
  }
  if (RegExp(r'已过期|已结束|已截止|\b(expired|ended|closed)\b').hasMatch(value)) {
    return XuexitongTaskStatus.closed;
  }
  return XuexitongTaskStatus.unknown;
}
