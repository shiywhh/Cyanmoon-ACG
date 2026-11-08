import 'package:flutter/material.dart';
import 'cycani_models.dart';

class CatalogLibraryToolbar extends StatelessWidget {
  const CatalogLibraryToolbar({
    super.key,
    required this.search,
    required this.listMode,
    required this.onSearch,
    required this.onView,
  });
  final TextEditingController search;
  final bool listMode;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onView;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SearchBar(
          controller: search,
          hintText: '搜索',
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          onChanged: onSearch,
        ),
      ),
      const SizedBox(width: 12),
      IconButton(
        tooltip: '网格视图',
        isSelected: !listMode,
        onPressed: () => onView(false),
        icon: const Icon(Icons.grid_view_rounded),
      ),
      IconButton(
        tooltip: '列表视图',
        isSelected: listMode,
        onPressed: () => onView(true),
        icon: const Icon(Icons.view_list_rounded),
      ),
    ],
  );
}

CycaniJson catalogLibraryItem(
  CycaniJson row, {
  required bool giri,
  required bool history,
}) {
  final anime = cycaniMap(row['animes']);
  final id = cycaniInt(row[giri ? 'vod_id' : 'anime_id']);
  return {
    'video_id': id,
    'title': giri
        ? row['vod_name'] ?? ''
        : row['anime_title'] ?? anime['title'] ?? row['title'] ?? '',
    'cover_url': giri
        ? row['vod_pic'] ?? row['pic'] ?? ''
        : row['anime_cover_url'] ??
              row['cover_url'] ??
              anime['cover_url'] ??
              anime['cover'] ??
              '',
    'catalog_source': giri ? 'giri' : 'xifan',
    if (!giri && history) 'resume_episode_id': row['episode_id'],
    if (!giri && history) 'resume_position_ms': row['position_ms'],
    'version': giri
        ? row['type_name'] ?? ''
        : history && row['episode_number'] != null
        ? '第${row['episode_number'].toString().replaceFirst(RegExp(r'\.0+$'), '')}集'
        : '',
  };
}
