String sourceCommentDate(Object? value) {
  final text = value?.toString() ?? '';
  final number = int.tryParse(text);
  final date = number != null && number > 0 && number < 99999999999999
      ? DateTime.fromMillisecondsSinceEpoch(
          number < 100000000000 ? number * 1000 : number,
        )
      : DateTime.tryParse(text)?.toLocal();
  if (date == null || date.millisecondsSinceEpoch == 0) return '';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}
