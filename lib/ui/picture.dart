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
  late Future<ImageProvider?> small = _official();
  late Future<ImageProvider?> scan = _scan();
  late Future<ImageProvider?>? large = _large();

  Future<ImageProvider?>? _large() =>
      widget.large ? _official(large: true) : null;

  Future<ImageProvider?> _official({bool large = false}) =>
      _available(Pictures.shared.official(widget.card.id, large: large));

  Future<ImageProvider?> _scan() =>
      _available(Pictures.shared.scanThumbnail(widget.card.id));

  Future<ImageProvider?> _available(Future<ImageProvider?> source) async {
    try {
      return await source;
    } on Exception {
      return null;
    }
  }

  late final StreamSubscription<String> _photos;

  @override
  void initState() {
    super.initState();
    _photos = Pictures.shared.photos.listen((id) {
      if (id != widget.card.id) return;
      setState(() {
        small = _official();
        scan = _scan();
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
      small = _official();
      scan = _scan();
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
        child: widget.large ? _image(large, _thumbnail) : _thumbnail(),
      ),
    ),
  );

  Widget _thumbnail() => _image(small, () => _image(scan, _placeholder));

  Widget _image(Future<ImageProvider?>? source, Widget Function() fallback) =>
      FutureBuilder<ImageProvider?>(
        key: ValueKey(widget.card.id),
        future: source,
        builder: (_, snapshot) {
          final image = snapshot.connectionState == ConnectionState.done
              ? snapshot.data
              : null;
          if (image == null) return fallback();
          return Image(
            image: image,
            fit: BoxFit.contain,
            frameBuilder: (_, child, frame, _) =>
                frame == null ? fallback() : child,
            errorBuilder: (_, _, _) => fallback(),
          );
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
