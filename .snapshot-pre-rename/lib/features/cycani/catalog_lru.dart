import 'dart:collection';

class CatalogLru<K, V> extends MapBase<K, V> {
  CatalogLru({this.capacity = 60}) : assert(capacity > 0);
  final int capacity;
  final _values = LinkedHashMap<K, V>();
  @override
  V? operator [](Object? key) {
    if (!_values.containsKey(key)) return null;
    final value = _values.remove(key) as V;
    _values[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, V value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > capacity) {
      _values.remove(_values.keys.first);
    }
  }

  @override
  Iterable<K> get keys => _values.keys.toList(growable: false);
  @override
  bool containsKey(Object? key) => _values.containsKey(key);
  @override
  V? remove(Object? key) => _values.remove(key);
  @override
  void clear() => _values.clear();
}
