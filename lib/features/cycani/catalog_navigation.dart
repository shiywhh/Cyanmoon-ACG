import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_item.dart';
import 'catalog_identity.dart';
import 'catalog_detail_page.dart';

Future<void> openCatalogItem(BuildContext context, BangumiItem item) async {
  final entry = SiteEntry.fromLegacy(item.id);
  if (entry != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogDetailPage(
          row: {
            'video_id': entry.rawId,
            'catalog_source': entry.source.name,
            'title': item.nameCn.isNotEmpty ? item.nameCn : item.name,
            'cover_url': item.images['large'],
          },
        ),
      ),
    );
  } else {
    // Legacy Bangumi entries have no implicit mapping to a site's raw ID.
    await context.pushNamed('/info/', arguments: item);
  }
}
