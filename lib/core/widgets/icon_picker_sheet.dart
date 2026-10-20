import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../icons/centli_icon_catalog.dart';
import 'centli_icon.dart';

/// Result of the icon picker: catalog key, hanzi value, or clear (null).
class IconPickerResult {
  const IconPickerResult({this.iconKey});

  /// Stored value for DB (`restaurant`, `hanzi:餐`, or null = auto).
  final String? iconKey;
}

/// Full-page Finch-style icon library (sidebar groups + 4-col colorful grid).
Future<IconPickerResult?> showCentliIconPicker(
  BuildContext context, {
  String? currentIconKey,
  String entityName = '',
}) {
  return Navigator.of(context).push<IconPickerResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => IconLibraryPage(
        currentIconKey: currentIconKey,
        entityName: entityName,
      ),
    ),
  );
}

class IconLibraryPage extends StatefulWidget {
  const IconLibraryPage({super.key, this.currentIconKey, this.entityName = ''});

  final String? currentIconKey;
  final String entityName;

  @override
  State<IconLibraryPage> createState() => _IconLibraryPageState();
}

class _IconLibraryPageState extends State<IconLibraryPage> {
  late String? _selected = widget.currentIconKey;
  late int _groupIndex;
  late final TextEditingController _hanziCtrl;
  String? _hanziError;

  /// 0 = SVG catalog, 1 = 汉字 fallback panel
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final existing = parseCentliHanzi(widget.currentIconKey);
    _hanziCtrl = TextEditingController(text: existing ?? '');
    _groupIndex = _initialGroupIndex();
    if (existing != null) _tab = 1;
  }

  int _initialGroupIndex() {
    final key = (widget.currentIconKey ?? '').trim();
    if (key.isEmpty || isCentliHanziIcon(key)) return 0;
    final groups = centliIconGroups;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].entries.any((e) => e.key == key)) return i;
    }
    return 0;
  }

  @override
  void dispose() {
    _hanziCtrl.dispose();
    super.dispose();
  }

  void _applyHanzi() {
    final raw = _hanziCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _hanziError = '请输入 1～2 个汉字');
      return;
    }
    final chars = raw.runes.map(String.fromCharCode).toList();
    if (chars.length > kCentliHanziMaxChars) {
      setState(() => _hanziError = '最多 2 个字符');
      return;
    }
    final encoded = encodeCentliHanzi(raw);
    if (encoded == null) {
      setState(() => _hanziError = '无效输入');
      return;
    }
    Navigator.pop(context, IconPickerResult(iconKey: encoded));
  }

  void _useNameInitials() {
    final init = initialsFromName(widget.entityName);
    if (init == '?' || init.isEmpty) {
      setState(() => _hanziError = '请先填写名称');
      return;
    }
    final encoded = encodeCentliHanzi(init);
    Navigator.pop(context, IconPickerResult(iconKey: encoded));
  }

  String _previewLabel() {
    final key = (_selected ?? '').trim();
    if (key.isEmpty) return '自动（按名称推断）';
    final hanzi = parseCentliHanzi(key);
    if (hanzi != null) return '汉字 · $hanzi';
    final e = centliIconByKey[key];
    if (e != null) return '${e.label} · ${e.key}';
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = centliIconGroups;
    final group = groups[_groupIndex.clamp(0, groups.length - 1)];

    return CentliGradientScaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '图标库',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const IconPickerResult(iconKey: null),
                    ),
                    child: const Text('自动'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: CentliSoftCard(
                padding: const EdgeInsets.all(CentliSpacing.cardPad),
                child: Row(
                  children: [
                    CentliIconChip(
                      name: widget.entityName.isEmpty
                          ? '图标'
                          : widget.entityName,
                      iconKey: _selected,
                      size: 52,
                      roundedSquare: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _previewLabel(),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    if (_selected != null)
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          context,
                          IconPickerResult(iconKey: _selected),
                        ),
                        child: const Text('选用'),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegTab(
                        label: '图标',
                        selected: _tab == 0,
                        onTap: () => setState(() => _tab = 0),
                      ),
                    ),
                    Expanded(
                      child: _SegTab(
                        label: '汉字',
                        selected: _tab == 1,
                        onTap: () => setState(() => _tab = 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CentliSpacing.item),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: CentliSoftCard(
                  child: _tab == 0
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 78,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: groups.length,
                                itemBuilder: (context, i) {
                                  final selected = i == _groupIndex;
                                  return InkWell(
                                    onTap: () =>
                                        setState(() => _groupIndex = i),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? CentliTheme.softBlue.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        groups[i].title,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? CentliTheme.softBlue
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Container(width: 1, color: const Color(0xFFEEEEEE)),
                            Expanded(
                              child: MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.2,
                                child: GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 4,
                                        mainAxisSpacing: 10,
                                        crossAxisSpacing: 8,
                                        childAspectRatio: 0.68,
                                      ),
                                  itemCount: group.entries.length,
                                  itemBuilder: (context, i) {
                                    final e = group.entries[i];
                                    final selected = _selected == e.key;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () {
                                        setState(() => _selected = e.key);
                                        Navigator.pop(
                                          context,
                                          IconPickerResult(iconKey: e.key),
                                        );
                                      },
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final labelH = 14.0;
                                          final gap = 2.0;
                                          final iconSize =
                                              (constraints.maxHeight -
                                                      labelH -
                                                      gap)
                                                  .clamp(32.0, 48.0);
                                          final side =
                                              iconSize < constraints.maxWidth
                                              ? iconSize
                                              : constraints.maxWidth;
                                          return Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: side,
                                                height: side,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                    border: Border.all(
                                                      color: selected
                                                          ? CentliTheme.softBlue
                                                          : const Color(
                                                              0xFFE8E8E8,
                                                            ),
                                                      width: selected ? 2 : 1,
                                                    ),
                                                  ),
                                                  child: CentliIconChip(
                                                    name: e.label,
                                                    iconKey: e.key,
                                                    size: (side - 4).clamp(
                                                      28.0,
                                                      44.0,
                                                    ),
                                                    roundedSquare: true,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(height: gap),
                                              SizedBox(
                                                height: labelH,
                                                width: constraints.maxWidth,
                                                child: Text(
                                                  e.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        fontSize: 10,
                                                        height: 1.1,
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                        fontWeight: selected
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.all(CentliSpacing.cardPad),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '文字图标（1～2 个汉字）',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: CentliSpacing.section),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _hanziCtrl,
                                      maxLength: kCentliHanziMaxChars,
                                      inputFormatters: [
                                        LengthLimitingTextInputFormatter(
                                          kCentliHanziMaxChars,
                                        ),
                                      ],
                                      decoration: InputDecoration(
                                        hintText: '例如：餐、工资',
                                        border: const OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(14),
                                          ),
                                        ),
                                        isDense: true,
                                        counterText: '',
                                        errorText: _hanziError,
                                      ),
                                      onChanged: (_) {
                                        if (_hanziError != null) {
                                          setState(() => _hanziError = null);
                                        }
                                      },
                                      onSubmitted: (_) => _applyHanzi(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _applyHanzi,
                                    child: const Text('使用'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: CentliSpacing.item),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _useNameInitials,
                                  icon: const Icon(Icons.text_fields, size: 18),
                                  label: const Text('用名称首字'),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Selected pill must keep label contrast in dark mode (white + onSurface was unreadable).
    final bg = !selected
        ? Colors.transparent
        : (dark ? scheme.primaryContainer : Colors.white);
    final fg = !selected
        ? scheme.onSurfaceVariant
        : (dark ? scheme.onPrimaryContainer : scheme.onSurface);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: fg,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
