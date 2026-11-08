import 'package:flutter/material.dart';

class CatalogCommentHeader extends StatelessWidget {
  const CatalogCommentHeader({
    super.key,
    required this.title,
    this.sort,
    this.refresh,
  });
  final String title;
  final Widget? sort;
  final VoidCallback? refresh;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (sort != null) sort!,
      IconButton(
        onPressed: refresh,
        icon: const Icon(Icons.refresh),
        tooltip: '刷新评论',
      ),
    ],
  );
}

class CatalogCommentComposer extends StatelessWidget {
  const CatalogCommentComposer({
    super.key,
    required this.controller,
    required this.send,
    this.busy = false,
    this.hint = '写下你的感想…',
  });
  final TextEditingController controller;
  final VoidCallback? send;
  final bool busy;
  final String hint;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 10),
      TextField(
        controller: controller,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: FilledButton(
            onPressed: busy ? null : send,
            child: Text(busy ? '发送中…' : '发布'),
          ),
        ),
      ),
    ],
  );
}

class CatalogCommentCard extends StatelessWidget {
  const CatalogCommentCard({
    super.key,
    required this.author,
    required this.content,
    required this.date,
    this.pinned = false,
    this.headerActions = const [],
    this.actions = const [],
    this.replies = const [],
  });
  final String author, content, date;
  final bool pinned;
  final List<Widget> headerActions, actions, replies;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  author,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (pinned) const Chip(label: Text('置顶')),
              ...headerActions,
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(content),
          const SizedBox(height: 8),
          if (date.isNotEmpty)
            Text(date, style: Theme.of(context).textTheme.bodySmall),
          Wrap(alignment: WrapAlignment.end, children: actions),
          ...replies,
        ],
      ),
    ),
  );
}
