import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'scanner.dart';
import 'scan_destination.dart';
import 'scan_reviews.dart';
import 'style.dart';
import 'sheets.dart';
import 'glass_sheet.dart';
import 'collection_light.dart';
import 'collection_browser.dart';
import 'collection_menu.dart';
import 'album.dart';
import 'library_style.dart';
import 'backup_panel.dart';
import 'catalog_search.dart';
import 'picture.dart';

Future<void> _openScanner(BuildContext context) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const Scanner()));

class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  Future<void> _create(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const CollectionNameDialog(),
    );
    if (title == null || !context.mounted) return;
    await context.read<AppModel>().create(title);
    if (context.mounted) await _open(context);
  }

  Future<void> _open(
    BuildContext context, {
    String? initialName,
    bool review = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          CollectionPage(initialName: initialName, initialReview: review),
    ),
  );

  Future<void> _openAlbum(
    BuildContext context,
    int id, {
    String? name,
    bool review = false,
  }) async {
    final model = context.read<AppModel>();
    await model.select(id);
    if (context.mounted &&
        model.state.folder == id &&
        ModalRoute.isCurrentOf(context) == true) {
      await _open(context, initialName: name, review: review);
    }
  }

  Future<void> _scan(BuildContext context) async {
    final model = context.read<AppModel>();
    final groups = model.state.groups;
    if (groups.isEmpty) return;
    final folder = groups.length == 1
        ? groups.single.id
        : await showLibrarySheet<int>(context, ScanDestination(groups));
    if (!context.mounted || folder == null) return;
    await model.select(folder);
    if (context.mounted &&
        model.state.folder == folder &&
        ModalRoute.isCurrentOf(context) == true) {
      await _openScanner(context);
    }
  }

  Future<void> _catalog(BuildContext context, {bool mine = false}) async {
    final model = context.read<AppModel>();
    final catalog = model.state.catalog;
    if (catalog == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CatalogSearchPage(catalog, model, initialMine: mine),
      ),
    );
  }

  Future<void> _review(BuildContext context, LibraryState state) async {
    final groups = state.groups
        .where((g) => state.pendingByFolder.containsKey(g.id))
        .toList();
    if (groups.isEmpty) return;
    final id = groups.length == 1
        ? groups.single.id
        : await showLibrarySheet<int>(
            context,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHeading('В каком альбоме проверить карты?'),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final g in groups)
                        ListTile(
                          title: Text(g.name),
                          trailing: Text('${state.pendingByFolder[g.id]}'),
                          onTap: () => Navigator.pop(context, g.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
    if (context.mounted && id != null) {
      await _openAlbum(context, id, review: true);
    }
  }

  AppBar _toolbar(BuildContext context, AppModel model) {
    final ready = model.catalog != null;
    return AppBar(
      forceMaterialTransparency: true,
      foregroundColor: libraryInk,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      flexibleSpace: const _LibraryAcrylic(),
      title: const Row(
        children: [
          LibraryGlass(
            radius: 12,
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Mark(size: 25, color: libraryInk),
            ),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Картовед',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: headingFont,
                fontWeight: FontWeight.w900,
                color: libraryInk,
                fontSize: 23,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'База карт',
          onPressed: ready
              ? () => showLibrarySheet<void>(context, CatalogPanel(model))
              : null,
          icon: const Icon(Icons.storage_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: LibraryGlass(
            radius: 12,
            child: IconButton(
              tooltip: 'Резервная копия',
              onPressed: model.libraryReady
                  ? () => showLibrarySheet<void>(context, BackupPanel(model))
                  : null,
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(BuildContext context, LibraryState state) {
    final pending = state.pendingByFolder.values.fold(0, (sum, n) => sum + n);
    return LibraryGlass(
      radius: 17,
      onTap: pending == 0 ? null : () => _review(context, state),
      child: Semantics(
        button: true,
        enabled: pending > 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 14,
                color: pending > 0 ? const Color(0xffe88a1a) : libraryMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'На проверке · $pending',
                  style: const TextStyle(
                    color: libraryInk,
                    fontSize: 16,
                    fontFamily: bodyFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (pending > 0)
                const Icon(Icons.chevron_right_rounded, color: libraryInk),
            ],
          ),
        ),
      ),
    );
  }

  Widget _libraryBody(BuildContext context, LibraryState state) {
    final model = context.read<AppModel>();
    final ready = state.catalog != null;
    return SafeArea(
      top: false,
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + 12,
                  16,
                  16,
                ),
                sliver: SliverList.list(
                  children: [
                    AlbumHeader(
                      albums: state.groups.length,
                      cards: state.groups.fold(0, (sum, g) => sum + g.count),
                      onCreate: model.libraryReady
                          ? () => _create(context)
                          : null,
                      onSearch: ready ? () => _catalog(context) : null,
                    ),
                    if (state.error case final error?)
                      TextButton(
                        onPressed: model.initialize,
                        style: TextButton.styleFrom(
                          foregroundColor: libraryInk,
                        ),
                        child: Text('$error. Повторить'),
                      )
                    else if (!ready)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(color: libraryMuted),
                      ),
                  ],
                ),
              ),
              if (state.groups.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: AlbumShelf(
                    state.groups,
                    state.covers,
                    (id) => _openAlbum(context, id),
                  ),
                )
              else if (model.libraryReady)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Пока нет альбомов. Создайте первый кнопкой «+».',
                      style: TextStyle(color: libraryInk),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                sliver: SliverList.list(
                  children: [
                    _reviewRow(context, state),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Недавно добавленные',
                          style: TextStyle(
                            fontFamily: headingFont,
                            color: libraryInk,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                          ),
                        ),
                        TextButton(
                          onPressed: ready
                              ? () => _catalog(context, mine: true)
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: libraryMuted,
                          ),
                          child: const Text('Все карты'),
                        ),
                      ],
                    ),
                    _RecentAdditions(
                      state,
                      (entry) => _openAlbum(
                        context,
                        entry.folder,
                        name: entry.card.name,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final model = context.read<AppModel>();
      final ready = state.catalog != null;
      final catalog = ready ? () => _catalog(context) : null;

      return DecoratedBox(
        decoration: librarySky,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.98, -.92),
              radius: 1.15,
              colors: [Color(0xffffc6ac), Color(0x00ffc6ac)],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: _toolbar(context, model),
            body: Builder(
              builder: (bodyContext) => _libraryBody(bodyContext, state),
            ),
            bottomNavigationBar: _LibraryNavigation(
              onScan: ready && state.groups.isNotEmpty
                  ? () => _scan(context)
                  : null,
              onCatalog: catalog,
            ),
          ),
        ),
      );
    },
  );
}

class _LibraryAcrylic extends StatelessWidget {
  const _LibraryAcrylic();

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: const ColoredBox(
        color: Color(0x36fff7ff),
        child: SizedBox.expand(),
      ),
    ),
  );
}

class _LibraryNavigation extends StatelessWidget {
  const _LibraryNavigation({required this.onScan, required this.onCatalog});
  final VoidCallback? onScan, onCatalog;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 9),
          child: LibraryGlass(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const _LibraryTab(
                    Icons.collections_bookmark_outlined,
                    'Альбомы',
                    selected: true,
                  ),
                  _LibraryTab(
                    Icons.center_focus_strong,
                    'Сканер',
                    semanticLabel: 'Сканировать карту',
                    onTap: onScan,
                  ),
                  _LibraryTab(
                    Icons.search_rounded,
                    'Каталог',
                    onTap: onCatalog,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab(
    this.icon,
    this.label, {
    this.semanticLabel,
    this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected || onTap != null ? libraryInk : libraryMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: selected || onTap != null,
        label: semanticLabel ?? label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? const Color(0xaafdf9ff) : null,
              borderRadius: BorderRadius.circular(15),
              border: selected ? Border.all(color: libraryRim) : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: bodyFont,
                    fontSize: 13,
                    color: color,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentAdditions extends StatelessWidget {
  const _RecentAdditions(this.state, this.onOpen);

  final LibraryState state;
  final ValueChanged<LibraryAddition> onOpen;

  @override
  Widget build(BuildContext context) {
    final albums = {for (final group in state.groups) group.id: group.name};
    return LibraryGlass(
      child: state.additions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Подтверждённые карты появятся здесь',
                style: TextStyle(color: libraryMuted),
              ),
            )
          : Column(
              children: [
                for (final (index, entry) in state.additions.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  ListTile(
                    leading: SizedBox(
                      width: 34,
                      height: 48,
                      child: ExcludeSemantics(
                        child: CardPicture(entry.card, tilt: false),
                      ),
                    ),
                    textColor: libraryInk,
                    title: Text(
                      entry.card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: entry.card.detail,
                            style: const TextStyle(
                              fontFamily: monoFont,
                              color: libraryMuted,
                            ),
                          ),
                          if (albums[entry.folder] case final album?)
                            TextSpan(text: ' · $album'),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      '×${entry.quantity}',
                      style: const TextStyle(
                        fontFamily: monoFont,
                        color: libraryMuted,
                      ),
                    ),
                    onTap: () => onOpen(entry),
                  ),
                ],
              ],
            ),
    );
  }
}

class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    this.initialName,
    this.initialReview = false,
  });
  final bool initialReview;
  final String? initialName;
  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late bool reviewOnly = widget.initialReview;

  Future<void> _rescan(ScanEntry entry) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => Scanner(rescan: entry)),
    );
    if (mounted && result != null) _message(context, result);
  }

  Future<void> _flag(BuildContext context, Edition card, bool value) async {
    try {
      await context.read<AppModel>().setFlag(card, value);
    } catch (_) {
      if (context.mounted) _message(context, 'Не удалось сохранить флажок');
    }
  }

  void _message(BuildContext context, String text, [SnackBarAction? action]) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: noticeDuration,
        persist: false,
        content: Text(text),
        action: action,
      ),
    );
  }

  Future<void> _remove(BuildContext context, Edition card) async {
    final model = context.read<AppModel>();
    try {
      final removed = await model.remove(card);
      if (!context.mounted || removed.scans.isEmpty) return;
      final count = removed.scans.fold(0, (n, scan) => n + scan.quantity);
      _message(
        context,
        'Убрано: ${card.name} ×$count',
        SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await model.restore(removed);
            } catch (_) {
              if (context.mounted) {
                _message(context, 'Не удалось вернуть карту');
              }
            }
          },
        ),
      );
    } catch (_) {
      if (context.mounted) _message(context, 'Не удалось убрать карту');
    }
  }

  Future<void> _export(BuildContext context) async {
    final model = context.read<AppModel>();
    try {
      final folder = model.state.folder;
      if (model.state.reviews.isNotEmpty) {
        final proceed = await reviewBeforeExport(
          context,
          model,
          () => _showReviews(true),
        );
        if (!proceed || !context.mounted || model.state.folder != folder) {
          return;
        }
      }
      final flaggedOnly = model.state.flags.isEmpty
          ? false
          : await showLibrarySheet<bool>(
              context,
              Builder(
                builder: (sheet) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SheetHeading('Экспорт для Moxfield'),
                    ListTile(
                      leading: const Icon(Icons.collections_bookmark_outlined),
                      title: const Text('Вся коллекция'),
                      onTap: () => Navigator.pop(sheet, false),
                    ),
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('Только отмеченные'),
                      onTap: () => Navigator.pop(sheet, true),
                    ),
                  ],
                ),
              ),
            );
      if (flaggedOnly == null ||
          model.state.folder != folder ||
          !context.mounted) {
        return;
      }
      final name = model.state.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final suffix = flaggedOnly ? '_Отмеченные' : '';
      final csv = await model.export(flaggedOnly: flaggedOnly);
      await AndroidActions.saveCsv('$name${suffix}_Moxfield.csv', csv);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: noticeDuration,
            content: Text('Не удалось сохранить CSV'),
          ),
        );
      }
    }
  }

  void _showReviews(bool value) {
    FocusScope.of(context).unfocus();
    setState(() => reviewOnly = value);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final items = state.printings;
      final count = items.fold(0, (total, item) => total + item.quantity);
      final names = items.map((item) => item.card.name).toSet().length;
      final foils = items
          .where((item) => item.card.foil)
          .fold(0, (n, item) => n + item.quantity);
      final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
      return CollectionLight(
        cardIds: items.map((item) => item.card.id),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: libraryInk,
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.dark,
            titleSpacing: 6,
            toolbarHeight: 12 + MediaQuery.textScalerOf(context).scale(66),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: headingFont,
                    color: libraryInk,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                Tooltip(
                  message: 'Названий · $names\nФольга · $foils',
                  child: Text(
                    cardCount(count),
                    style: const TextStyle(
                      fontFamily: bodyFont,
                      color: libraryMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Экспорт для Moxfield',
                onPressed: items.isEmpty || state.catalog == null
                    ? null
                    : () => _export(context),
                icon: const Icon(Icons.ios_share_outlined),
              ),
              if (state.groups.isNotEmpty) CollectionMenu(state),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilterChip(
                          avatar: !reviewOnly && state.reviews.isNotEmpty
                              ? const Icon(
                                  Icons.circle,
                                  size: 11,
                                  color: Color(0xffb66614),
                                )
                              : null,
                          label: Text('На проверке · ${state.reviews.length}'),
                          selected: reviewOnly,
                          backgroundColor: const Color(0xd9faf5ff),
                          selectedColor: const Color(0xffffe1bb),
                          checkmarkColor: libraryInk,
                          side: const BorderSide(color: libraryRim),
                          labelStyle: const TextStyle(
                            fontFamily: bodyFont,
                            color: libraryInk,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: _showReviews,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: IndexedStack(
                          index: reviewOnly ? 1 : 0,
                          sizing: StackFit.expand,
                          children: [
                            if (items.isEmpty)
                              Center(
                                child: Text(
                                  state.reviews.isEmpty
                                      ? 'Пока нет карт'
                                      : 'Карты ожидают проверки',
                                  style: const TextStyle(color: libraryMuted),
                                ),
                              )
                            else
                              CollectionBrowser(
                                initialName: widget.initialName,
                                key: ValueKey(state.folder),
                                catalog: state.catalog,
                                items: items,
                                flags: state.flags,
                                onFlag: (card, value) =>
                                    _flag(context, card, value),
                                onRemove: (card) => _remove(context, card),
                              ),
                            if (reviewOnly)
                              ReviewList(
                                onRescan: state.catalog == null
                                    ? null
                                    : _rescan,
                                onBackToAlbum: () => _showReviews(false),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: keyboard
              ? null
              : _ScanButton(enabled: state.catalog != null),
        ),
      );
    },
  );
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                if (enabled)
                  Positioned.fill(
                    left: 6,
                    right: 6,
                    top: 5,
                    child: IgnorePointer(
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 14,
                          sigmaY: 10,
                        ),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: libraryActionCorners,
                            gradient: libraryActionGradient,
                          ),
                        ),
                      ),
                    ),
                  ),
                LibraryActionButton(
                  onPressed: enabled ? () => _openScanner(context) : null,
                  icon: Icons.center_focus_strong,
                  label: 'Сканировать карту',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
