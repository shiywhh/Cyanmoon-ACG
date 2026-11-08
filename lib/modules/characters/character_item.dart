import 'package:cyanmoon_acg/modules/characters/actor_item.dart';

class CharacterAvator {
  final String small;
  final String medium;
  final String grid;
  final String large;

  CharacterAvator({
    required this.small,
    required this.medium,
    required this.grid,
    required this.large,
  });

  factory CharacterAvator.fromJson(Map<String, dynamic> json) {
    return CharacterAvator(
      small: json['small'] ?? '',
      medium: json['medium'] ?? '',
      grid: json['grid'] ?? '',
      large: json['large'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'small': small,
      'medium': medium,
      'grid': grid,
      'large': large,
    };
  }
}

class CharacterExtraInfo {
  String nameCn;
  String summary;

  CharacterExtraInfo({required this.nameCn, required this.summary});

  factory CharacterExtraInfo.fromJson(Map<String, dynamic> json) {
    String nameCn = '';
    // infobox 可能为空列表或缺失，取值前必须判空。
    final infobox = json['infobox'];
    if (infobox is List && infobox.isNotEmpty) {
      final first = infobox.first;
      if (first is Map && first['key'] == '简体中文名') {
        nameCn = first['value']?.toString() ?? '';
      }
    }
    return CharacterExtraInfo(
        nameCn: nameCn, summary: json['summary']?.toString() ?? '');
  }
}

class CharacterItem {
  final int id;
  final int type;
  final String name;
  final String relation;
  final CharacterAvator avator;
  final List<ActorItem> actorList;
  CharacterExtraInfo info;

  CharacterItem(
      {required this.id,
      required this.type,
      required this.name,
      required this.relation,
      required this.avator,
      required this.actorList,
      required this.info});

  factory CharacterItem.fromJson(Map<String, dynamic> json) {
    // 无 cast 的角色 actors 为 null，无图角色 images 为 null，均需兜底。
    final actors = json['actors'] as List? ?? [];
    List<ActorItem> resActorList =
        actors.map((i) => ActorItem.fromJson(i)).toList();
    final images = json['images'];
    return CharacterItem(
        id: json['id'] ?? 0,
        type: json['type'] ?? 0,
        name: json['name'] ?? '',
        relation: json['relation'] ?? '未知',
        avator: CharacterAvator.fromJson(
            images is Map<String, dynamic> ? images : const {}),
        actorList: resActorList,
        info: CharacterExtraInfo(nameCn: '', summary: ''));
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'relation': relation,
      'images': avator.toJson(),
      'actors': actorList.map((e) => e.toJson()).toList(),
    };
  }
}
