import 'package:flutter/material.dart';
import 'package:antlr4/antlr4.dart';
import 'package:cyanmoon_acg/services/logging/logger.dart';
import 'package:cyanmoon_acg/bbcode/bbcode_elements.dart';

import 'generated/BBCodeListener.dart';
import 'generated/BBCodeParser.dart';

class BBCodeBaseListener implements BBCodeListener {
  final List<dynamic> bbcode = [];

  /// 记录进入标签时的位置（同类嵌套用栈，后进先出）
  void _enterTag(TagContext ctx) {
    final tagName = ctx.tagName?.text;

    switch (tagName) {
      case 'URL':
      case 'url':
      case 'USER':
      case 'user':
        bbCodeTag.link.add(bbcode.length);
        break;
      case 'QUOTE':
      case 'quote':
        bbCodeTag.quoted.add(bbcode.length);
        break;
      case 'B':
      case 'b':
        bbCodeTag.bold.add(bbcode.length);
        break;
      case 'I':
      case 'i':
        bbCodeTag.italic.add(bbcode.length);
        break;
      case 'S':
      case 's':
        bbCodeTag.strikeThrough.add(bbcode.length);
        break;
      case 'U':
      case 'u':
        bbCodeTag.underline.add(bbcode.length);
        break;
      case 'PHOTO':
      case 'photo':
      case 'IMG':
      case 'img':
        bbCodeTag.img.add(bbcode.length);
        break;
      case 'MASK':
      case 'mask':
        bbCodeTag.masked.add(bbcode.length);
        break;
      case 'SIZE':
      case 'size':
        bbCodeTag.size.add(bbcode.length);
        break;
      case 'COLOR':
      case 'color':
        bbCodeTag.color.add(bbcode.length);
        break;
      default:
        CyanmoonLogger().e(
            'BBCode: unrecognized Tag: ${ctx.text}, please submit an issue with logs, bangumi, and episode information');
        break;
    }
  }

  /// 对标签内所有的 BBCodeText 叠加样式
  void _exitTag(TagContext ctx) {
    final tagName = ctx.tagName?.text;

    switch (tagName) {
      case 'URL':
      case 'url':
        {
          if (bbCodeTag.link.isEmpty) break;
          final start = bbCodeTag.link.removeLast();
          if (start < bbcode.length && bbcode[start] is BBCodeText) {
            if (ctx.attr != null) {
              bbcode[start].link = ctx.attr!.text;
            } else {
              bbcode[start].link = bbcode[start].text;
            }
          }
        }
        break;
      case 'USER':
      case 'user':
        {
          if (bbCodeTag.link.isEmpty) break;
          final start = bbCodeTag.link.removeLast();
          if (start < bbcode.length &&
              ctx.attr != null &&
              bbcode[start] is BBCodeText) {
            bbcode[start].link = 'https://bangumi.tv/user/${ctx.attr!.text}';
            bbcode[start].text = '@${bbcode[start].text}';
          }
        }
        break;
      case 'QUOTE':
      case 'quote':
        {
          if (bbCodeTag.quoted.isEmpty) break;
          final start = bbCodeTag.quoted.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].quoted = true;
            }
          }
          // Add icon to the end of quoted text (仅最外层引用补图标，嵌套不再重复)
          if (bbCodeTag.quoted.isEmpty) {
            bbcode.add(const Icon(Icons.format_quote));
          }
        }
        break;
      case 'B':
      case 'b':
        {
          if (bbCodeTag.bold.isEmpty) break;
          final start = bbCodeTag.bold.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].bold = true;
            }
          }
        }
        break;
      case 'I':
      case 'i':
        {
          if (bbCodeTag.italic.isEmpty) break;
          final start = bbCodeTag.italic.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].italic = true;
            }
          }
        }
        break;
      case 'S':
      case 's':
        {
          if (bbCodeTag.strikeThrough.isEmpty) break;
          final start = bbCodeTag.strikeThrough.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].strikeThrough = true;
            }
          }
        }
        break;
      case 'U':
      case 'u':
        {
          if (bbCodeTag.underline.isEmpty) break;
          final start = bbCodeTag.underline.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].underline = true;
            }
          }
        }
        break;
      case 'PHOTO':
      case 'photo':
      case 'IMG':
      case 'img':
        {
          if (bbCodeTag.img.isEmpty) break;
          final start = bbCodeTag.img.removeLast();
          if (start < bbcode.length &&
              bbcode.isNotEmpty &&
              bbcode[start] is BBCodeText) {
            bbcode[start] = BBCodeImg(imageUrl: bbcode[start].text);
          }
        }
        break;
      case 'MASK':
      case 'mask':
        {
          if (bbCodeTag.masked.isEmpty) break;
          final start = bbCodeTag.masked.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].masked = true;
            }
          }
        }
        break;
      case 'SIZE':
      case 'size':
        {
          // attr 是可选的（如 "[size]"），且可能不是纯数字，解析失败时忽略该标签而不是抛异常。
          final size = int.tryParse(ctx.attr?.text ?? '');
          if (size != null) {
            if (bbCodeTag.size.isEmpty) break;
            final start = bbCodeTag.size.removeLast();
            for (int i = start; i < bbcode.length; i++) {
              if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
                bbcode[i].size = size;
              }
            }
          }
        }
        break;
      case 'COLOR':
      case 'color':
        {
          if (bbCodeTag.color.isEmpty) break;
          final start = bbCodeTag.color.removeLast();
          for (int i = start; i < bbcode.length; i++) {
            if (bbcode.isNotEmpty && bbcode[i] is BBCodeText) {
              bbcode[i].color = ctx.attr?.text;
            }
          }
        }
        break;
      default:
        CyanmoonLogger().e(
            'BBCode: unrecognized Tag: ${ctx.text}, please submit an issue with logs, bangumi, and episode information');
        break;
    }
  }

  @override
  void enterDocument(DocumentContext ctx) {}

  @override
  void exitDocument(DocumentContext ctx) {}

  @override
  void enterElement(ElementContext ctx) {}

  @override
  void exitElement(ElementContext ctx) {}

  @override
  void enterTag(TagContext ctx) {
    _enterTag(ctx);
  }

  @override
  void exitTag(TagContext ctx) {
    _exitTag(ctx);
  }

  @override
  void enterPlain(PlainContext ctx) {
    bbcode.add(BBCodeText(text: ctx.text));
  }

  @override
  void exitPlain(PlainContext ctx) {}

  @override
  void enterBgm(BgmContext ctx) {
    /// 处理 (bgm35) 类型的表情
    bbcode.add(BBCodeBgm(id: int.tryParse(ctx.id!.text!) ?? 0));
  }

  @override
  void exitBgm(BgmContext ctx) {}

  @override
  void enterMusume(MusumeContext ctx) {
    /// 处理 (musume_07) 类型的表情
    bbcode.add(BBCodeMusume(id: int.tryParse(ctx.id!.text!) ?? 0));
  }

  @override
  void exitMusume(MusumeContext ctx) {}

  @override
  void enterSticker(StickerContext ctx) {
    /// 处理 (=A=) 类型的表情
    /// ctx.start!.type 为 BBCode.tokens 内的 token 值
    bbcode.add(BBCodeSticker(id: ctx.start!.type - 11));
  }

  @override
  void exitSticker(StickerContext ctx) {}

  @override
  void enterEveryRule(ParserRuleContext ctx) {}

  @override
  void exitEveryRule(ParserRuleContext ctx) {}

  @override
  void visitTerminal(TerminalNode node) {}

  @override
  void visitErrorNode(ErrorNode node) {}
}
