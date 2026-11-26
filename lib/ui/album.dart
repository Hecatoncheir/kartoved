import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/catalog.dart';
import 'library_style.dart';
import 'picture.dart';
import 'style.dart';

class AlbumHeader extends StatelessWidget {
  const AlbumHeader({
    super.key,
    required this.albums,
    required this.cards,
    this.onCreate,
    this.onSearch,
  });
  final int albums, cards;
  final VoidCallback? onCreate, onSearch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    context.strings.library,
                    style: TextStyle(
                      fontFamily: headingFont,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      letterSpacing: -1.3,
                      color: libraryInk,
                    ),
                  ),
                ),
                Text(
                  '${context.strings.albumCount(albums)} · ${context.strings.cardCount(cards)}',
                  style: const TextStyle(
                    fontFamily: bodyFont,
                    fontSize: 16,
                    color: libraryMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: libraryActionSurface,
            child: IconButton(
              tooltip: context.strings.createCollection,
              onPressed: onCreate,
              color: Colors.white,
              icon: const Icon(Icons.add, size: 30),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Semantics(
        container: true,
        button: true,
        label: context.strings.findCard,
        enabled: onSearch != null,
        onTap: onSearch,
        excludeSemantics: true,
        child: LibraryGlass(
          radius: 15,
          onTap: onSearch,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: libraryMuted),
                SizedBox(width: 9),
                Flexible(
                  child: Text(
                    context.strings.findCard,
                    style: TextStyle(
                      fontSize: 17,
                      color: libraryMuted,
                      fontFamily: bodyFont,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class AlbumShelf extends StatelessWidget {
  const AlbumShelf(this.groups, this.covers, this.onOpen, {super.key});
  final List<CardGroup> groups;
  final Map<int, List<Edition>> covers;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    // Первым показываем самый ранний альбом, остальные — от новых к старым.
    final primary = groups.last;
    final shelf = SliverList.separated(
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final group = index == 0 ? primary : groups[index - 1];
        void open() => onOpen(group.id);
        return Semantics(
          key: ValueKey(group.id),
          button: true,
          label: '${group.name}, ${context.strings.cardCount(group.count)}',
          excludeSemantics: true,
          onTap: open,
          child: LibraryGlass(
            onTap: open,
            child: _AlbumPocket(
              group: group,
              cards: covers[group.id] ?? const [],
              featured: index == 0,
            ),
          ),
        );
      },
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) =>
          SliverOpacity(opacity: value, sliver: child),
      child: shelf,
    );
  }
}

class _AlbumPocket extends StatelessWidget {
  const _AlbumPocket({
    required this.group,
    required this.cards,
    required this.featured,
  });
  final CardGroup group;
  final List<Edition> cards;
  final bool featured;

  Widget _cards() {
    if (cards.isEmpty) {
      const art = ['forest', 'dragon', 'island'];
      return Image.asset(
        'assets/design/${art[(group.id - 1) % art.length]}-cover.webp',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      );
    }
    final slots = featured ? 3 : 2;
    return LayoutBuilder(
      builder: (_, size) {
        final width = math.min(
          180.0,
          (size.maxWidth - (slots - 1) * 4) / slots,
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (index, card) in cards.take(slots).indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              SizedBox(
                width: width,
                height: double.infinity,
                child: CardPicture(
                  card,
                  tilt: false,
                  fit: BoxFit.cover,
                  placeholder: _CardBack(card.name),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _name(double size) => Text(
    group.name,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: libraryInk,
      fontFamily: headingFont,
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.12,
    ),
  );
  Widget _count(BuildContext context) => Text(
    context.strings.cardCount(group.count),
    style: const TextStyle(
      fontFamily: bodyFont,
      fontSize: 15,
      color: libraryMuted,
    ),
  );
  static const _arrow = Icon(Icons.chevron_right_rounded, color: libraryInk);

  @override
  Widget build(BuildContext context) {
    if (!featured) {
      return Padding(
        padding: const EdgeInsets.all(9),
        child: Row(
          children: [
            Flexible(
              flex: 4,
              fit: FlexFit.tight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(height: 68, child: _cards()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _name(18),
                  const SizedBox(height: 3),
                  _count(context),
                ],
              ),
            ),
            _arrow,
          ],
        ),
      );
    }
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 21;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 15, 12, 7),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _cards(),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 130),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: libraryRim),
                    gradient: const LinearGradient(
                      colors: [Color(0xe2f1eaff), Color(0xe5e3e6f7)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: stacked
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [_name(21), _count(context)],
                                )
                              : _name(21),
                        ),
                        if (!stacked) ...[
                          const SizedBox(width: 8),
                          _count(context),
                        ],
                        const SizedBox(width: 3),
                        _arrow,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffaca0c9)),
      borderRadius: BorderRadius.circular(5),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffdcd7ee), Color(0xffc8bddc)],
      ),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: bodyFont,
            color: libraryInk,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    ),
  );
}
