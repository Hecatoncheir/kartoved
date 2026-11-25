import 'package:material_ui/material_ui.dart';

const scanInk = Color(0xff11162b);
const scanPaper = Color(0xfffff0df);
const scanMuted = Color(0xffd9cbe5);
const scanOrange = Color(0xffff942f);
const scanBackdrop = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xff533357), Color(0xff251e45), Color(0xff132d48)],
);

class ScanSurface extends StatelessWidget {
  const ScanSurface({super.key, required this.child, this.radius = 18});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xe24a3759), Color(0xf02b2943), Color(0xeb253951)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x667f91b5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x32100e20),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}
