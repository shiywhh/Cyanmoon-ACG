import 'package:kazumi/services/network/catalog_image_url.dart';
import 'package:kazumi/features/cycani/catalog_identity.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';

typedef CatalogJson = Map<String, dynamic>;

CatalogJson catalogMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<CatalogJson> catalogList(dynamic value) {
  if (value is Map) value = value['list'] ?? value['items'] ?? [];
  return value is List ? value.whereType<Map>().map(catalogMap).toList() : [];
}

int catalogInt(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

List<String> catalogUniqueLabels(
  Iterable<String> values, {
  Iterable<String> exclude = const [],
}) {
  String normalized(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_,，]+'), '');
  final seen = exclude.map(normalized).toSet();
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(normalized(value))) value.trim(),
  ];
}

class CatalogVideo {
  const CatalogVideo(this.json);
  final CatalogJson json;
  int get id => catalogInt(json['video_id'] ?? json['id']);
  String get title => '${json['title'] ?? '未命名番剧'}';
  String get cover {
    final url = '${json['cover_url'] ?? ''}';
    return json['catalog_source'] == 'giri'
        ? CatalogImageUrl.giriPublic(url)
        : url;
  }

  String get description => '${json['description'] ?? ''}';
  int get bangumiId => catalogInt(json['bangumi_id']);
  int get total => catalogInt(json['total']);
  List<CatalogJson> get sources => catalogList(json['play_from']);

  /// A separate ID namespace keeps existing Kazumi/Bangumi records intact.
  ///
  /// 按行内 catalog_source 生成站点感知的 BangumiItem（legacy 负 ID 编码），
  /// 稀饭/Giri 行不再被硬编码成次元城身份；次元城行的编码与旧实现完全一致。
  BangumiItem toBangumi() {
    final source = CatalogSource.values.firstWhere(
      (s) => s.name == '${json['catalog_source']}',
      orElse: () => CatalogSource.cycani,
    );
    final entry = id > 0 ? SiteEntry(source, id) : null;
    return BangumiItem(
      id: entry?.legacyId ?? 0,
      type: 2,
      name: title,
      nameCn: title,
      summary: description,
      airDate: '${json['publish_date'] ?? ''}',
      airWeekday: catalogInt(json['weekday']),
      rank: 0,
      images: {
        for (final key in ['large', 'common', 'medium', 'small', 'grid'])
          key: cover,
      },
      tags: [],
      metaTags: catalogUniqueLabels([
        if (json['air'] is String && '${json['air']}'.trim().isNotEmpty)
          '${json['air']}'.trim(),
        if (total > 0) '$total 话',
        for (final key in ['version', 'area', 'category'])
          if (json[key] is String) '${json[key]}',
      ]),
      alias: ['${json['subtitle'] ?? ''}'],
      ratingScore: double.tryParse('${json['score']}') ?? 0,
      votes: catalogInt(json['score_num']),
      votesCount: [],
      info: entry?.key ?? '',
    );
  }
}

class CatalogEpisodes {
  const CatalogEpisodes({
    required this.name,
    required this.code,
    required this.items,
  });
  final String name;
  final String code;
  final List<CatalogJson> items;
  Road toRoad() => Road(
    name: name,
    data: items
        .map((e) => 'https://www.cycani.org/section/${e['id']}')
        .toList(),
    identifier: [
      for (var i = 0; i < items.length; i++)
        '${items[i]['title'] ?? '第${i + 1}集'}',
    ],
  );
}

/// Strict host/path checking prevents forwarding a session to arbitrary URLs.
int? cycaniSectionId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'www.cycani.org' ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final match = RegExp(r'^/section/([1-9][0-9]*)$').firstMatch(uri.path);
  return match == null ? null : int.tryParse(match[1]!);
}
