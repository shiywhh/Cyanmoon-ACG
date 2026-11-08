import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/core_module.dart';
import 'package:cyanmoon_acg/pages/index_module.dart';

final appModule = createModule(
  register: (c) {
    c
      ..module(coreModule)
      ..module(indexModule);
  },
);
