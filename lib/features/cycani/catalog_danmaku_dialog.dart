import 'package:flutter/material.dart';
import 'cycani_api.dart';

typedef CatalogDanmakuSender =
    Future<void> Function(
      String content,
      double time, {
      required String mode,
      required int color,
    });

class CatalogDanmakuDialog extends StatefulWidget {
  const CatalogDanmakuDialog({
    super.key,
    this.sectionId,
    this.sourceName = '次元城',
    this.send,
    this.onSent,
    required this.position,
  }) : assert(sectionId != null || send != null);
  final int? sectionId;
  final String sourceName;
  final CatalogDanmakuSender? send;
  final VoidCallback? onSent;
  final double Function() position;
  @override
  State<CatalogDanmakuDialog> createState() => _CatalogDanmakuDialogState();
}

class _CatalogDanmakuDialogState extends State<CatalogDanmakuDialog> {
  final text = TextEditingController();
  String mode = 'normal';
  int color = 0xFFFFFF;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy || text.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sender =
          widget.send ??
          (
            String content,
            double time, {
            required String mode,
            required int color,
          }) => CycaniApi.instance.postDanmaku(
            widget.sectionId!,
            content,
            time,
            mode: mode,
            color: color,
          );
      await sender(text.text, widget.position(), mode: mode, color: color);
      if (mounted) {
        widget.onSent?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('发送${widget.sourceName}弹幕'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: text,
            enabled: !busy,
            maxLength: 100,
            autofocus: true,
            decoration: const InputDecoration(labelText: '弹幕内容'),
            onSubmitted: (_) => _send(),
          ),
          DropdownButton<String>(
            value: mode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'normal', child: Text('滚动')),
              DropdownMenuItem(value: 'top', child: Text('顶部')),
              DropdownMenuItem(value: 'bottom', child: Text('底部')),
            ],
            onChanged: busy ? null : (v) => setState(() => mode = v!),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final c in [
                0xFFFFFF,
                0xFF5A6E,
                0xFFCC00,
                0x42D9ED,
                0x80ED99,
              ])
                ChoiceChip(
                  selected: color == c,
                  label: Icon(Icons.circle, color: Color(0xFF000000 | c)),
                  onSelected: busy ? null : (_) => setState(() => color = c),
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: busy ? null : _send,
        child: Text(busy ? '发送中…' : '发送'),
      ),
    ],
  );
}
