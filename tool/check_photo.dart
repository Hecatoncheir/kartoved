import 'dart:io';

import 'package:kartoved/data/oracle.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Укажите каталог Oracle, путь к снимку и при необходимости ожидаемый индекс.',
    );
    exitCode = 64;
    return;
  }
  final hits = identify(args[0], args[1]);
  stdout.writeln(hits);
  if (args.length == 3 &&
      (hits.isEmpty || hits.first.index != int.parse(args[2]))) {
    exitCode = 1;
  }
}
