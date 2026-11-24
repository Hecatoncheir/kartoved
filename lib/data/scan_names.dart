import 'dart:convert';

import 'package:flutter/services.dart';

import 'catalog.dart';

class ScanNames {
  const ScanNames(this.catalog);

  final Catalog catalog;

  static Future<Map<String, List<dynamic>>>? _aliases;

  static Future<Map<String, List<dynamic>>> _loadAliases() async {
    try {
      final data = await rootBundle.loadString(
        'assets/oracle/scan_names.json',
        cache: false,
      );
      return (jsonDecode(data) as Map<String, dynamic>)
          .cast<String, List<dynamic>>();
    } catch (_) {
      _aliases = null;
      return {};
    }
  }

  Future<List<String>> search(String input) async {
    final term = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[’‘]'), "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    if (term.isEmpty) return [];

    final matches = [<String>{}, <String>{}, <String>{}];
    for (final name in await catalog.searchNames(term)) {
      matches[_rank(name.toLowerCase(), term) ?? 2].add(name);
    }
    final aliases = await (_aliases ??= _loadAliases());
    for (final entry in aliases.entries) {
      for (final alias in entry.value.cast<String>()) {
        if (_rank(alias, term) case final rank?) matches[rank].add(entry.key);
      }
    }
    return {...matches[0], ...matches[1], ...matches[2]}.take(60).toList();
  }

  static int? _rank(String name, String term) {
    if (name == term) return 0;
    if (name.startsWith(term)) return 1;
    return name.contains(term) ? 2 : null;
  }
}
