import 'package:flutter/material.dart';
import 'catalog_models.dart';

class CatalogDetailMetadata extends StatelessWidget {
  const CatalogDetailMetadata({
    super.key,
    required this.video,
    required this.actions,
    this.episodes,
  });
  final CatalogVideo video;
  final int? episodes;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final data = video.json;
    final subtitle = catalogUniqueLabels(
      '${data['subtitle'] ?? ''}'.split(RegExp('[,，\\n]')),
      exclude: [video.title],
    ).join(' / ');
    final facts = catalogUniqueLabels([
      for (final key in ['year', 'area', 'version'])
        if (data[key] != null) '${data[key]}',
      if ((episodes ?? video.total) > 0) '${episodes ?? video.total} 集',
      if ((double.tryParse('${data['score']}') ?? 0) > 0) '评分 ${data['score']}',
    ]);
    final tags = catalogUniqueLabels(
      (data['tags'] is List ? data['tags'] as List : const []).map((e) => '$e'),
      exclude: [
        for (final key in ['year', 'area', 'version']) '${data[key]}',
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          video.title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            facts.join('  ·  '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final tag in tags.take(12))
                Chip(
                  label: Text(tag),
                  side: BorderSide.none,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 10, children: actions),
      ],
    );
  }
}
