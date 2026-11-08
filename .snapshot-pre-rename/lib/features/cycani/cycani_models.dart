import 'package:kazumi/services/network/catalog_image_url.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';

typedef CycaniJson = Map<String, dynamic>;

CycaniJson cycaniMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<CycaniJson> cycaniList(dynamic value) {
  if (value is Map) value = value['list'] ?? value['items'] ?? [];
  return value is List ? value.whereType<Map>().map(cycaniMap).toList() : [];
}

int cycaniInt(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

List<String> cycaniUniqueLabels(
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

class CycaniVideo {
  const CycaniVideo(this.json);
  final CycaniJson json;
  int get id => cycaniInt(json['video_id'] ?? json['id']);
  String get title => '${json['title'] ?? '未命名番剧'}';
  String get cover {
    final url = '${json['cover_url'] ?? ''}';
    return json['catalog_source'] == 'giri'
        ? CatalogImageUrl.giriPublic(url)
        : url;
  }

  String get description => '${json['description'] ?? ''}';
  int get bangumiId => cycaniInt(json['bangumi_id']);
  int get total => cycaniInt(json['total']);
  List<CycaniJson> get sources => cycaniList(json['play_from']);

  /// A separate ID namespace keeps existing Kazumi/Bangumi records intact.
  BangumiItem toBangumi() => BangumiItem(
    id: -id,
    type: 2,
    name: title,
    nameCn: title,
    summary: description,
    airDate: '${json['publish_date'] ?? ''}',
    airWeekday: cycaniInt(json['weekday']),
    rank: 0,
    images: {
      for (final key in ['large', 'common', 'medium', 'small', 'grid'])
        key: cover,
    },
    tags: [],
    metaTags: cycaniUniqueLabels([
      if (total > 0) '$total 话',
      for (final key in ['version', 'area', 'category'])
        if (json[key] is String) '${json[key]}',
    ]),
    alias: ['${json['subtitle'] ?? ''}'],
    ratingScore: double.tryParse('${json['score']}') ?? 0,
    votes: cycaniInt(json['score_num']),
    votesCount: [],
    info: 'cycani:$id',
  );
}

class CycaniEpisodes {
  const CycaniEpisodes({
    required this.name,
    required this.code,
    required this.items,
  });
  final String name;
  final String code;
  final List<CycaniJson> items;
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
