import 'package:material_ui/material_ui.dart';

import 'style.dart';

const libraryInk = Color(0xff24183f);
const libraryMuted = Color(0xff574c6c);
const libraryRim = Color(0xbbffffff);

const libraryActionCorners = BorderRadius.all(Radius.circular(15));
const libraryActionGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xffffac51), Color(0xffed661b)],
);
const libraryActionSurface = BoxDecoration(
  borderRadius: libraryActionCorners,
  gradient: libraryActionGradient,
  boxShadow: [
    BoxShadow(color: Color(0x45da6b3d), offset: Offset(0, 4), blurRadius: 9),
  ],
);

const librarySky = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xffd5c2f4), Color(0xffeddef7), Color(0xffe4e8fa)],
  ),
);

final libraryTheme = ThemeData(
  fontFamily: bodyFont,
  colorScheme: ColorScheme.fromSeed(seedColor: libraryInk).copyWith(
    primary: libraryInk,
    onSurface: libraryInk,
    onSurfaceVariant: libraryMuted,
    surface: const Color(0xfff8f3fc),
    outlineVariant: const Color(0xffcfc4df),
  ),
);

class LibraryActionButton extends StatelessWidget {
  const LibraryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: onPressed == null
        ? const BoxDecoration()
        : libraryActionSurface,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const RoundedRectangleBorder(borderRadius: libraryActionCorners),
        backgroundColor: Colors.transparent,
        foregroundColor: libraryInk,
        disabledBackgroundColor: const Color(0xffe2dbee),
        disabledForegroundColor: libraryMuted,
        shadowColor: Colors.transparent,
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
    ),
  );
}

class LibraryGlass extends StatelessWidget {
  const LibraryGlass({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 20,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: const [
          BoxShadow(
            color: Color(0x244e3a70),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: corners,
            border: Border.all(color: libraryRim),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xd6fffaff), Color(0x8bede6fa), Color(0xbbe1e5f8)],
            ),
          ),
          child: onTap == null
              ? child
              : InkWell(
                  onTap: onTap,
                  splashColor: const Color(0x2256418a),
                  hoverColor: const Color(0x1456418a),
                  child: child,
                ),
        ),
      ),
    );
  }
}

String _quantity(int count, String one, String few, String many) {
  final word = switch ((count % 100, count % 10)) {
    (>= 11 && <= 14, _) => many,
    (_, 1) => one,
    (_, >= 2 && <= 4) => few,
    _ => many,
  };
  return '$count $word';
}

String albumCount(int n) => _quantity(n, 'альбом', 'альбома', 'альбомов');
String cardCount(int n) => _quantity(n, 'карта', 'карты', 'карт');
