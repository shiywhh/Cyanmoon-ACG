import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class CycaniAvatarStore extends ChangeNotifier {
  CycaniAvatarStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  static final instance = CycaniAvatarStore();
  final Future<Directory> Function() _directory;
  Future<void>? _ready;
  late Directory _root;
  final Map<String, String> _files = {};
  Future<void> initialize() => _ready ??= _load();
  Future<void> _load() async {
    _root = Directory('${(await _directory()).path}/cycani_avatars');
    await _root.create(recursive: true);
    final index = File('${_root.path}/index.json');
    if (!await index.exists()) return;
    final value = jsonDecode(await index.readAsString());
    if (value is Map) {
      for (final item in value.entries) {
        final name = '${item.value}';
        if (RegExp(
          r'^(?:[0-9]+|source-[0-9a-f]{64})\.(png|jpg|jpeg|webp)$',
        ).hasMatch(name))
          _files['${item.key}'] = name;
      }
    }
  }

  String? pathFor(int id) => _pathFor('$id');
  String? sourcePath(String source, String user) =>
      _pathFor(_sourceKey(source, user));
  String _sourceKey(String source, String user) =>
      'source-${sha256.convert(utf8.encode('$source:$user'))}';

  String? _pathFor(String key) {
    final name = _files[key];
    return name == null ? null : '${_root.path}/$name';
  }

  Future<void> _save() async {
    final temp = File('${_root.path}/index.json.tmp');
    await temp.writeAsString(jsonEncode(_files), flush: true);
    await temp.rename('${_root.path}/index.json');
  }

  Future<void> choose(int id) async {
    if (id <= 0) throw StateError('请先登录');
    await _choose('$id');
  }

  Future<void> chooseSource(String source, String user) async {
    if (user.trim().isEmpty) throw StateError('请先登录');
    await _choose(_sourceKey(source, user));
  }

  Future<void> _choose(String key) async {
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 90,
    );
    if (selected != null) await _setFile(key, selected);
  }

  Future<void> setFile(int id, XFile selected) async {
    if (id <= 0) throw StateError('请先登录');
    await _setFile('$id', selected);
  }

  Future<void> _setFile(String key, XFile selected) async {
    await initialize();
    if (await selected.length() > 8 * 1024 * 1024)
      throw StateError('图片不能超过 8 MB');
    var extension = selected.path.split('.').last.toLowerCase();
    if (!['png', 'jpg', 'jpeg', 'webp'].contains(extension)) extension = 'jpg';
    final name = '$key.$extension';
    final target = File('${_root.path}/$name');
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(await selected.readAsBytes(), flush: true);
    await temp.rename(target.path);
    _files[key] = name;
    await _save();
    await FileImage(target).evict();
    notifyListeners();
  }

  Future<void> clear(int id) => _clear('$id');
  Future<void> clearSource(String source, String user) =>
      _clear(_sourceKey(source, user));

  Future<void> _clear(String key) async {
    await initialize();
    _files.remove(key);
    await _save();
    notifyListeners();
  }
}
