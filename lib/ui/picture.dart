import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/pictures.dart';
import 'style.dart';
import 'card_tilt.dart';

class CardPicture extends StatefulWidget {
  const CardPicture(this.card, {super.key, this.slot = 0, this.large = false});
  final Edition card;
  final int slot;
  final bool large;
  @override
  State<CardPicture> createState() => _CardPictureState();
}

class _CardPictureState extends State<CardPicture> {
  late Future<ImageProvider> file = Pictures.shared.get(widget.card.id);
  late Future<ImageProvider>? large = _large();
  Future<ImageProvider>? _large() =>
      widget.large ? Pictures.shared.get(widget.card.id, large: true) : null;

  late final StreamSubscription<String> _photos;

  @override
  void initState() {
    super.initState();
    _photos = Pictures.shared.photos.listen((id) {
      if (id != widget.card.id) return;
      setState(() {
        file = Pictures.shared.get(id);
        large = _large();
      });
    });
  }

  @override
  void dispose() {
    _photos.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CardPicture old) {
    super.didUpdateWidget(old);
    if (old.card.id != widget.card.id) {
      file = Pictures.shared.get(widget.card.id);
    }
    if (old.large != widget.large || old.card.id != widget.card.id) {
      large = _large();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${widget.card.name}, ${widget.card.detail}${widget.card.foil ? ', фольга' : ''}',
    image: true,
    child: TiltCard(
      slot: widget.slot,
      foil: widget.card.foil,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: !widget.large
            ? _thumbnail()
            : FutureBuilder<ImageProvider>(
                future: large,
                builder: (context, full) {
                  if (full.connectionState == ConnectionState.done &&
                      full.hasData) {
                    return Image(
                      image: full.requireData,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _thumbnail(),
                    );
                  }
                  return _thumbnail();
                },
              ),
      ),
    ),
  );

  Widget _thumbnail() => FutureBuilder<ImageProvider>(
    future: file,
    builder: (c, s) {
      if (s.connectionState == ConnectionState.done && s.hasData) {
        return Image(
          image: s.requireData,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _placeholder(),
        );
      }
      return _placeholder();
    },
  );

  Widget _placeholder() => ColoredBox(
    color: const Color(0xff504945),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Text(
          widget.card.name,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: paper,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  );
}
