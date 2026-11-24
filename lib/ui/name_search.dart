import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NameSearch extends Cubit<AsyncSnapshot<List<String>>> {
  NameSearch(this.lookup) : super(const AsyncSnapshot.nothing());
  final Future<List<String>> Function(String) lookup;
  Timer? timer;
  String query = '';
  int revision = 0;

  void search(String text) {
    timer?.cancel();
    final request = ++revision;
    query = text.trim();
    if (query.isEmpty) {
      emit(const AsyncSnapshot.nothing());
      return;
    }
    emit(const AsyncSnapshot.waiting());
    final term = query;
    timer = Timer(
      const Duration(milliseconds: 160),
      () => _read(term, request),
    );
  }

  Future<void> _read(String term, int request) async {
    try {
      final rows = await lookup(term);
      if (!isClosed && revision == request) {
        emit(AsyncSnapshot.withData(ConnectionState.done, rows));
      }
    } catch (error) {
      if (!isClosed && revision == request) {
        emit(AsyncSnapshot.withError(ConnectionState.done, error));
      }
    }
  }

  @override
  Future<void> close() {
    timer?.cancel();
    return super.close();
  }
}
