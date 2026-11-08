// 记录进入 tag 时 list 所在位置
class BBCodeTag {
  // 同类标签嵌套（如 [quote] 套 [quote]）时，单字段会被内层覆盖，
  // 外层退出时会从内层位置开始叠加样式导致区间错乱。改用栈保存各自起点。
  final List<int> bold = [];
  final List<int> italic = [];
  final List<int> underline = [];
  final List<int> strikeThrough = [];
  final List<int> masked = [];
  final List<int> quoted = [];
  final List<int> code = [];
  final List<int> size = [];
  final List<int> color = [];
  final List<int> link = [];
  final List<int> img = [];

  void clear() {
    bold.clear();
    italic.clear();
    underline.clear();
    strikeThrough.clear();
    masked.clear();
    quoted.clear();
    code.clear();
    size.clear();
    color.clear();
    link.clear();
    img.clear();
  }
}

class BBCodeText {
  String text;

  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strikeThrough = false;
  bool masked = false;
  bool quoted = false;
  bool code = false;

  int size = 14;
  String? color;
  String? link;

  BBCodeText({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikeThrough = false,
    this.masked = false,
    this.quoted = false,
    this.code = false,
    this.size = 14,
    this.color,
    this.link,
  });
}

class BBCodeBgm {
  int id;

  BBCodeBgm({required this.id});
}

class BBCodeMusume {
  int id;

  BBCodeMusume({required this.id});
}

class BBCodeSticker {
  int id;

  BBCodeSticker({required this.id});
}

class BBCodeImg {
  String imageUrl;

  BBCodeImg({required this.imageUrl});
}

BBCodeTag bbCodeTag = BBCodeTag();
