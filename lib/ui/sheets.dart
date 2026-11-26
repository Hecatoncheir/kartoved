import '../l10n/strings.dart';
import 'picture.dart';
import '../data/pictures.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../data/catalog.dart';
import '../data/browser.dart';
import '../model.dart';
import 'card_facts.dart';
import 'edition_picker.dart';
import 'glass_sheet.dart';
import 'library_style.dart';
import 'style.dart';

class ResultSheet extends StatefulWidget {
  const ResultSheet(
    this.matches,
    this.initial, {
    super.key,
    this.action,
    this.owned,
  });
  final List<Match> matches;
  final Edition initial;
  final String? action;
  final int Function(String name)? owned;
  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  int selected = 0;
  late Edition card = widget.initial;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeading(context.strings.scanResult),
        const SizedBox(height: 18),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 66,
                height: 90,
                child: CardPicture(card, large: true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      fontFamily: headingFont,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(card.detail, style: codeText),
                  if (widget.owned case final count?)
                    Text(context.strings.ownedCount(count(card.name))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.matches[selected].editions.length > 1)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.layers_outlined),
            title: Text(context.strings.printingAndLanguage),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final edition = await showEditionPicker(
                context,
                widget.matches[selected].editions,
                card,
              );
              if (edition != null && mounted) setState(() => card = edition);
            },
          ),
        if (widget.matches.length > 1)
          ExpansionTile(
            key: ValueKey(selected),
            tilePadding: EdgeInsets.zero,
            title: Text(context.strings.otherMatches),
            children: [
              for (final (i, match) in widget.matches.indexed)
                if (i != selected)
                  ListTile(
                    title: Text(match.editions.first.name),
                    subtitle: Text(
                      match.editions.first.detail,
                      style: codeText,
                    ),
                    onTap: () => setState(() {
                      selected = i;
                      card = match.editions.first;
                    }),
                  ),
            ],
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: Text(context.strings.foil),
          value: card.foil,
          onChanged: (value) => setState(() => card = card.withFoil(value)),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, card),
          icon: const Icon(Icons.check),
          label: Text(widget.action ?? context.strings.addToCollection),
        ),
        ScryfallLink(card),
        ExpansionTile(
          key: ValueKey(card.id),
          tilePadding: EdgeInsets.zero,
          title: Text(context.strings.textAndRules),
          children: [CardFacts(card, key: ValueKey(card.id))],
        ),
      ],
    ),
  );
}

Future<Edition?> choosePrinting(
  BuildContext context,
  Catalog catalog,
  Edition card, {
  bool library = false,
}) async {
  final editions = await catalog.byName(card.name);
  if (!context.mounted) return null;
  final options = editions
      .where((e) => card.language == 'und' || e.language == card.language)
      .toList();
  return showEditionPicker(context, options, card, library: library);
}

class CatalogPanel extends StatefulWidget {
  const CatalogPanel(this.model, {super.key});
  final AppModel model;
  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  String? message;
  bool loading = false;
  bool offlineReady = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _checkOffline();
  }

  Future<void> _checkOffline() async {
    try {
      final ready = await browserOfflineScanner(prepare: false);
      if (mounted && ready) setState(() => offlineReady = true);
    } catch (_) {
      // Пользователь может повторить проверку кнопкой подготовки.
    }
  }

  Future<void> _prepareOffline() async {
    setState(() {
      loading = true;
      message = context.strings.downloadingScannerFiles;
    });
    try {
      final ready = await browserOfflineScanner(prepare: true);
      if (mounted) {
        setState(() {
          offlineReady = ready;
          message = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = context.strings.saveScannerFilesFailed);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> update() async {
    final strings = context.strings;
    setState(() {
      loading = true;
      message = null;
    });
    String result;
    try {
      result = await widget.model.update()
          ? strings.databaseUpdated
          : strings.databaseUpToDate;
    } catch (e) {
      debugPrint('Обновление: $e');
      result = strings.databaseUpdateFailed;
    }
    if (mounted) {
      setState(() {
        message = result;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.model.catalog!.spec;
    final date = spec.created;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeading(context.strings.cardDatabase),
          const SizedBox(height: 18),
          LibraryGlass(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.strings.artworkCount(spec.count),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          context.strings.offlineDatabaseDate(
                            date.month.toString().padLeft(2, '0'),
                            date.day.toString().padLeft(2, '0'),
                            date.year,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (kIsWeb)
            OutlinedButton.icon(
              icon: Icon(
                offlineReady ? Icons.offline_pin : Icons.download_outlined,
              ),
              label: Text(
                offlineReady
                    ? context.strings.scannerOfflineReady
                    : context.strings.prepareOfflineScanner,
              ),
              onPressed: loading || offlineReady ? null : _prepareOffline,
            ),
          TextButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: Text(context.strings.offlineSetThumbnails),
            onPressed: loading
                ? null
                : () => showGlassSheet<void>(
                    context,
                    PicturePack(widget.model.catalog!),
                    library: true,
                  ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message!, semanticsLabel: message),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: loading ? null : update,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(
              loading && !kIsWeb
                  ? context.strings.updating
                  : kIsWeb
                  ? context.strings.reloadPage
                  : context.strings.checkUpdates,
            ),
          ),
        ],
      ),
    );
  }
}

class PicturePack extends StatefulWidget {
  const PicturePack(this.catalog, {super.key});
  final Catalog catalog;
  @override
  State<PicturePack> createState() => _PicturePackState();
}

class _PicturePackState extends State<PicturePack> {
  String code = '', language = 'en', status = '';
  bool loading = false;
  void progress(String text) {
    if (mounted) setState(() => status = text);
  }

  Future<void> download() async {
    final strings = context.strings;
    setState(() {
      loading = true;
      status = strings.findingPrintings;
    });
    try {
      final cards = await widget.catalog.inSet(
        code.trim().toLowerCase(),
        language.trim().toLowerCase(),
      );
      var done = 0;
      for (final card in cards) {
        if (!mounted) return;
        await Pictures.shared.official(card.id);
        progress(strings.downloadProgress(++done, cards.length));
      }
      progress(
        cards.isEmpty ? strings.setLanguageNotFound : strings.thumbnailsSaved,
      );
    } catch (_) {
      progress(strings.downloadInterrupted);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeading(context.strings.setThumbnails),
        const SizedBox(height: 16),
        TextField(
          enabled: !loading,
          decoration: InputDecoration(
            labelText: context.strings.setCode,
            hintText: 'SNC',
          ),
          onChanged: (v) => setState(() => code = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: language,
          enabled: !loading,
          decoration: InputDecoration(
            labelText: context.strings.cardLanguage,
            hintText: 'ru, en…',
          ),
          onChanged: (v) => setState(() => language = v),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(status),
          ),
        const SizedBox(height: 14),
        LibraryActionButton(
          icon: Icons.download_rounded,
          onPressed: code.trim().isEmpty || language.trim().isEmpty || loading
              ? null
              : download,
          label: context.strings.download,
        ),
      ],
    ),
  );
}
