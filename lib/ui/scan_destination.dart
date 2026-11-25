import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'style.dart';

class ScanDestination extends StatelessWidget {
  const ScanDestination(this.groups, {super.key});

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
