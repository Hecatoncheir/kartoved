import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'scanner.dart';
import 'scan_glass.dart';
import 'scan_reviews.dart';
import 'style.dart';
import 'sheets.dart';
import 'collection_light.dart';
import 'collection_browser.dart';
import 'album.dart';
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
      builder: (_) => const _NameDialog(),
    );
    if (title == null || !context.mounted) return;
    await context.read<AppModel>().create(title);
    if (context.mounted) await _open(context);
  }

  Future<void> _open(BuildContext context, {String? initialName}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CollectionPage(initialName: initialName),
        ),
      );

  Future<void> _openAlbum(BuildContext context, int id, {String? name}) async {
    final model = context.read<AppModel>();
    await model.select(id);
    if (context.mounted &&
        model.state.folder == id &&
        ModalRoute.isCurrentOf(context) == true) {
      await _open(context, initialName: name);
    }
  }

  Future<void> _scan(BuildContext context) async {
    final model = context.read<AppModel>();
    final groups = model.state.groups;
    if (groups.isEmpty) return;
    final folder = groups.length == 1
        ? groups.single.id
        : await panel<int>(context, _ScanDestination(groups));
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

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final model = context.read<AppModel>();
      final ready = state.catalog != null;
      final scan = ready && state.groups.isNotEmpty
          ? () => _scan(context)
          : null;
      final search = ready ? () => _catalog(context) : null;
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              _BrandMark(),
              SizedBox(width: 9),
              Flexible(
                child: Text('Картовед', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          titleTextStyle: const TextStyle(
            color: paper,
            fontFamily: headingFont,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
          actions: [
            IconButton(
              tooltip: 'Найти карту по названию',
              onPressed: search,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'Резервная копия',
              onPressed: state.groups.isEmpty
                  ? null
                  : () => panel<void>(context, BackupPanel(model)),
              icon: const Icon(Icons.settings_backup_restore_rounded),
            ),
            IconButton(
              tooltip: 'База карт',
              onPressed: !ready
                  ? null
                  : () => panel<void>(context, CatalogPanel(model)),
              icon: const Icon(Icons.storage_rounded),
            ),
          ],
        ),
        body: SafeArea(
          left: false,
          right: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: _LibraryContent(
                state: state,
                onRetry: model.initialize,
                onScan: scan,
                onCreate: ready ? () => _create(context) : null,
                onOpenAlbum: (id) => _openAlbum(context, id),
                onBrowse: ready ? () => _catalog(context, mine: true) : null,
                onOpenRecent: (entry) =>
                    _openAlbum(context, entry.folder, name: entry.card.name),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _LibraryNavigation(
          onScan: scan,
          onCatalog: search,
        ),
      );
    },
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: butter,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Padding(
      padding: EdgeInsets.all(5),
      child: Mark(size: 24, color: ink),
    ),
  );
}

class _LibraryNavigation extends StatelessWidget {
  const _LibraryNavigation({required this.onScan, required this.onCatalog});

  final VoidCallback? onScan;
  final VoidCallback? onCatalog;

  @override
  Widget build(BuildContext context) => NavigationBar(
    height: 68,
    destinations: [
      const NavigationDestination(
        icon: Icon(Icons.collections_bookmark_outlined, color: butter),
        label: 'Коллекции',
      ),
      NavigationDestination(
        enabled: onScan != null,
        icon: DecoratedBox(
          decoration: BoxDecoration(
            color: onScan == null ? raised : butter,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
            child: Icon(
              Icons.center_focus_strong,
              color: onScan == null ? muted : ink,
            ),
          ),
        ),
        label: 'Сканер',
      ),
      NavigationDestination(
        enabled: onCatalog != null,
        icon: const Icon(Icons.grid_view_rounded),
        label: 'Каталог',
      ),
    ],
    onDestinationSelected: (index) {
      switch (index) {
        case 1:
          onScan?.call();
        case 2:
          onCatalog?.call();
      }
    },
  );
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.state,
    required this.onRetry,
    required this.onScan,
    required this.onCreate,
    required this.onOpenAlbum,
    required this.onBrowse,
    required this.onOpenRecent,
  });

  final LibraryState state;
  final VoidCallback onRetry;
  final VoidCallback? onScan;
  final VoidCallback? onCreate;
  final ValueChanged<int> onOpenAlbum;
  final VoidCallback? onBrowse;
  final ValueChanged<LibraryAddition> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    const sides = EdgeInsets.symmetric(horizontal: 16);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: sides.copyWith(top: 10, bottom: 8),
          sliver: SliverList.list(
            children: [
              AlbumHeader(
                albums: state.groups.length,
                cards: state.groups.fold(0, (sum, group) => sum + group.count),
                onScan: onScan,
              ),
              if (state.error case final error?)
                TextButton(onPressed: onRetry, child: Text('$error. Повторить'))
              else if (state.catalog == null)
                const LinearProgressIndicator(),
              const SizedBox(height: 16),
              _LibrarySection(
                'Альбомы',
                OutlinedButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Создать коллекцию'),
                ),
              ),
            ],
          ),
        ),
        if (state.groups.isNotEmpty)
          AlbumShelf(state.groups, onOpenAlbum, padding: sides),
        SliverPadding(
          padding: sides.copyWith(top: 20, bottom: 22),
          sliver: SliverList.list(
            children: [
              _LibrarySection(
                'Недавно добавленные',
                TextButton.icon(
                  onPressed: onBrowse,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  iconAlignment: IconAlignment.end,
                  style: TextButton.styleFrom(
                    foregroundColor: aqua,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(
                      fontFamily: bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  label: const Text('Все карты'),
                ),
              ),
              const SizedBox(height: 6),
              _RecentAdditions(state, onOpenRecent),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection(this.title, this.action);

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontFamily: headingFont,
          fontSize: 21,
          fontWeight: FontWeight.w900,
        ),
      ),
      action,
    ],
  );
}

class _RecentAdditions extends StatelessWidget {
  const _RecentAdditions(this.state, this.onOpen);

  final LibraryState state;
  final ValueChanged<LibraryAddition> onOpen;

  @override
  Widget build(BuildContext context) {
    final albums = {for (final group in state.groups) group.id: group.name};
    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: outline),
        borderRadius: BorderRadius.circular(15),
      ),
      child: state.additions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Подтверждённые карты появятся здесь',
                style: TextStyle(color: muted),
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
                      child: ExcludeSemantics(child: CardPicture(entry.card)),
                    ),
                    title: Text(
                      entry.card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: entry.card.detail, style: codeText),
                          if (albums[entry.folder] case final album?)
                            TextSpan(text: ' · $album'),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text('×${entry.quantity}', style: codeText),
                    onTap: () => onOpen(entry),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ScanDestination extends StatelessWidget {
  const _ScanDestination(this.groups);

  final List<CardGroup> groups;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SheetHeading('В какой альбом сканировать?'),
      const SizedBox(height: 12),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: groups.length,
          itemBuilder: (_, index) {
            final group = groups[index];
            return ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text(group.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, group.id),
            );
          },
        ),
      ),
    ],
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  String value = '';
  void submit() {
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая коллекция'),
    content: TextField(
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: 'Название'),
      onChanged: (v) => setState(() => value = v.trim()),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: value.isEmpty ? null : submit,
        child: const Text('Создать'),
      ),
    ],
  );
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, this.initialName});
  final String? initialName;
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
    messenger.showSnackBar(SnackBar(content: Text(text), action: action));
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
        final proceed = await reviewBeforeExport(context, model);
        if (!proceed || !context.mounted || model.state.folder != folder) {
          return;
        }
      }
      final flaggedOnly = model.state.flags.isEmpty
          ? false
          : await panel<bool>(
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
          const SnackBar(content: Text('Не удалось сохранить CSV')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final items = state.printings;
      final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
      return CollectionLight(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            foregroundColor: paper,
            titleTextStyle: const TextStyle(
              color: paper,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              fontSize: 25,
            ),
            title: Text(state.title),
            actions: [
              IconButton(
                tooltip: 'Экспорт для Moxfield',
                onPressed: items.isEmpty ? null : () => _export(context),
                icon: const Icon(Icons.ios_share_outlined),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Column(
                children: [
                  if (state.reviews.isNotEmpty)
                    ReviewButton(
                      state.reviews.length,
                      () => openReviews(context, context.read<AppModel>()),
                    ),
                  if (items.isNotEmpty && !keyboard)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Frost(
                        radius: 16,
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: paper,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Nunito Sans',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 14,
                            ),
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'Карт · ${items.fold<int>(0, (a, b) => a + b.quantity)}',
                                ),
                                Text(
                                  'Названий · ${items.map((r) => r.card.name).toSet().length}',
                                ),
                                Text(
                                  'Фольга · ${items.where((r) => r.card.foil).fold<int>(0, (a, b) => a + b.quantity)}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? SafeArea(
                            top: false,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Folio(),
                                  Text(
                                    state.reviews.isEmpty
                                        ? 'Пока нет карт'
                                        : 'Карты ожидают проверки',
                                    style: const TextStyle(color: paper),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : CollectionBrowser(
                            initialName: initialName,
                            key: ValueKey(state.folder),
                            catalog: state.catalog,
                            items: items,
                            flags: state.flags,
                            onFlag: (card, value) =>
                                _flag(context, card, value),
                            onRemove: (card) => _remove(context, card),
                          ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: keyboard ? null : const _ScanButton(),
        ),
      );
    },
  );
}

class _ScanButton extends StatelessWidget {
  const _ScanButton();
  static const corners = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: ClipRRect(
        borderRadius: corners,
        child: ScanGlass(
          child: DecoratedBox(
            decoration: const ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: corners,
                side: BorderSide(color: Color(0x99ffda91)),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x80ffcf78),
                  Color(0x92ffbf55),
                  Color(0xa2efa244),
                  Color(0x84ffbc58),
                ],
                stops: [0, .20, .54, 1],
              ),
            ),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shape: const RoundedRectangleBorder(borderRadius: corners),
                foregroundColor: const Color(0xff090a07),
                elevation: 0,
              ),
              onPressed: () => _openScanner(context),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Сканировать карту'),
            ),
          ),
        ),
      ),
    ),
  );
}
