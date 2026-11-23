import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/pictures.dart';
import 'style.dart';
import 'card_tilt.dart';

class CardPicture extends StatefulWidget {
  const CardPicture(this.card, {super.key, this.slot = 0});
  final Edition card;
  final int slot;
  @override
  State<CardPicture> createState() => _CardPictureState();
}

class _CardPictureState extends State<CardPicture> {
  late Future<File> file = Pictures.shared.get(widget.card.id);
  @override
  void didUpdateWidget(CardPicture old) {
    super.didUpdateWidget(old);
    if (old.card.id != widget.card.id) {
      file = Pictures.shared.get(widget.card.id);
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
        child: FutureBuilder<File>(
          future: file,
          builder: (c, s) {
            if (s.connectionState == ConnectionState.done && s.hasData) {
              return Image.file(s.requireData, fit: BoxFit.contain);
            }
            return ColoredBox(
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
          },
        ),
      ),
    ),
  );
}
