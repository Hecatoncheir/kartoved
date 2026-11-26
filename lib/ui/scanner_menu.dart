import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/catalog.dart';
import '../data/recognition_result.dart';
import '../scan_cubit.dart';
import '../scan_decision.dart';
import 'batch_settings.dart';
import 'glass_sheet.dart';
import 'scanner_style.dart';
import 'scanner_strings.dart';
import 'style.dart';

enum ScannerMenuAction { targets, calibrate }

enum _Page {
  main,
  details,
  language,
  edition,
  model;

  String title(BuildContext context) => switch (this) {
    main => context.strings.scannerMenu,
    details => context.strings.batchAndRecognition,
    language => context.strings.batchLanguage,
    edition => context.strings.batchEdition,
    model => context.strings.recognitionModel,
  };
}

class ScannerMenu extends StatefulWidget {
  const ScannerMenu({
    super.key,
    required this.scan,
    required this.catalog,
    required this.rescan,
    required this.calibrated,
    required this.toggleOption,
    required this.toggleGuide,
    required this.toggleTorch,
    required this.selectModel,
  });

  final ScanCubit scan;
  final Catalog? catalog;
  final bool rescan, calibrated;
  final ValueChanged<ScanOption> toggleOption;
  final VoidCallback toggleGuide, toggleTorch;
  final ValueChanged<RecognitionModel> selectModel;

  @override
  State<ScannerMenu> createState() => _ScannerMenuState();
}

class _ScannerMenuState extends State<ScannerMenu> {
  _Page page = _Page.main;

  void _go(_Page next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => page = next);
  }

  void _back() => _go(page == _Page.details ? _Page.main : _Page.details);

  Widget _quick(ScanSession state) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.rescan)
          for (final option in ScanOption.values)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: scanOrange,
              activeThumbColor: scanPaper,
              inactiveTrackColor: const Color(0xff524d68),
              inactiveThumbColor: const Color(0xffddd5e2),
              title: Text(
                option == ScanOption.essentials
                    ? context.strings.essentialsOnly
                    : context.strings.consecutiveScan,
              ),
              subtitle: Text(
                option == ScanOption.essentials
                    ? context.strings.englishNameFirst
                    : context.strings.repeatSameCard,
              ),
              value: state.options.contains(option),
              onChanged: (_) => widget.toggleOption(option),
            ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _QuickButton(
              icon: Icons.crop_free,
              label: context.strings.frameAndGlass,
              selected: state.showGuide,
              toggle: widget.toggleGuide,
            ),
            _QuickButton(
              icon: Icons.flashlight_on_outlined,
              label: context.strings.torch,
              selected: state.light == ScanLight.on,
              toggle: state.light == ScanLight.unavailable
                  ? null
                  : widget.toggleTorch,
            ),
          ],
        ),
        const Divider(height: 28),
        _MenuRow(_Page.details.title(context), onTap: () => _go(_Page.details)),
      ],
    ),
  );

  Widget _details(ScanSession state) {
    final ready = widget.catalog != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MenuRow(
            _Page.language.title(context),
            value: BatchField.language.label(context, state.batch.language),
            onTap: ready ? () => _go(_Page.language) : null,
          ),
          _MenuRow(
            _Page.edition.title(context),
            value: BatchField.edition.label(context, state.batch.setCode),
            code: state.batch.setCode != null,
            onTap: ready ? () => _go(_Page.edition) : null,
          ),
          if (!widget.rescan)
            _MenuRow(
              context.strings.targetCards,
              value: switch (state.targets.length) {
                0 => context.strings.noTargetsSelected,
                1 => state.targets.single,
                final n => context.strings.targetsSelected(n),
              },
              onTap: ready
                  ? () => Navigator.pop(context, ScannerMenuAction.targets)
                  : null,
            ),
          _MenuRow(
            _Page.model.title(context),
            value: state.model.label(context),
            onTap: ready ? () => _go(_Page.model) : null,
          ),
          if (widget.calibrated && state.mode.usesTray)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.crop_free),
              title: Text(context.strings.recalibrateTray),
              onTap: () => Navigator.pop(context, ScannerMenuAction.calibrate),
            ),
        ],
      ),
    );
  }

  Widget _picker(BatchField field, BatchSettings batch) {
    final language = field == BatchField.language;
    final catalog = widget.catalog!;
    return BatchPicker(
      key: ValueKey(field),
      field: field,
      load: language ? catalog.languages : catalog.setCodes,
      selected: language ? batch.language : batch.setCode,
      onSelect: (code) {
        widget.scan.configure(
          BatchSettings(
            language: language ? code : batch.language,
            setCode: language ? batch.setCode : code,
          ),
        );
        _go(_Page.details);
      },
    );
  }

  Widget _models(ScanSession state) => ListView(
    children: [
      for (final model in RecognitionModel.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(model.label(context)),
          subtitle: Text(switch (model) {
            RecognitionModel.oracle => context.strings.oracleModelDescription,
            RecognitionModel.mtgIdentification =>
              context.strings.mtgModelDescription,
            RecognitionModel.keypoints =>
              context.strings.keypointModelDescription,
          }),
          trailing: model == state.model
              ? const Icon(Icons.check, color: scanOrange)
              : null,
          onTap: () {
            widget.selectModel(model);
            _go(_Page.details);
          },
        ),
    ],
  );

  Widget _body(ScanSession state) => switch (page) {
    _Page.main => _quick(state),
    _Page.details => _details(state),
    _Page.language => _picker(BatchField.language, state.batch),
    _Page.edition => _picker(BatchField.edition, state.batch),
    _Page.model => _models(state),
  };

  @override
  Widget build(BuildContext context) => PopScope<ScannerMenuAction>(
    canPop: page == _Page.main,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) _back();
    },
    child: GlassSheet(
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xffa7a2b7),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 46,
                child: page == _Page.main
                    ? null
                    : IconButton(
                        tooltip: context.strings.back,
                        onPressed: _back,
                        icon: const Icon(Icons.chevron_left),
                      ),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    page.title(context),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: headingFont,
                      fontSize: 21,
                      height: 1.12,
                      color: scanPaper,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.strings.closeMenu,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x306c7297),
                  foregroundColor: scanPaper,
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: BlocBuilder<ScanCubit, ScanSession>(
              bloc: widget.scan,
              builder: (_, state) => _body(state),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.toggle,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? toggle;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: Icon(icon, size: 19, color: toggle == null ? scanMuted : scanPaper),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        if (selected) ...[
          const SizedBox(width: 6),
          const Icon(Icons.check, size: 17, color: scanPaper),
        ],
      ],
    ),
    labelStyle: const TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w800,
      color: scanPaper,
    ),
    backgroundColor: const Color(0x44646a84),
    selectedColor: const Color(0x88665c78),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    side: const BorderSide(color: Color(0x66898aa6)),
    showCheckmark: false,
    selected: selected,
    onSelected: toggle == null ? null : (_) => toggle!(),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
    this.title, {
    required this.onTap,
    this.value,
    this.code = false,
  });
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool code;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: bodyFont,
                      color: scanPaper,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (value != null)
                  Expanded(
                    flex: 2,
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: code ? monoFont : bodyFont,
                        color: scanMuted,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: scanMuted),
              ],
            ),
          ),
        ),
      ),
      const Divider(height: 1),
    ],
  );
}
