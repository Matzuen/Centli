# -*- coding: utf-8 -*-
"""Patch DB searchTransactions + pubspec + manifests + bookkeeping voice."""
from __future__ import annotations
import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\Resource\Codebase\studyProject\Centli")

def patch_db():
    path = ROOT / r"lib\data\db\centli_database.dart"
    text = path.read_text(encoding="utf-8")
    old = '''  /// P2 bill search: keyword match on note, merchant, and amount (major units).
  Future<List<Transaction>> searchTransactions(
    String ledgerId,
    String query, {
    int limit = 100,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final pattern = '%${q.toLowerCase()}%';
    final amountMinors = _amountMinorCandidates(q);

    final rows = await (select(transactions)
          ..where((t) {
            final base = t.ledgerId.equals(ledgerId) & t.deletedAt.isNull();
            Expression<bool> textHit = t.merchant.lower().like(pattern) |
                t.note.lower().like(pattern);
            if (amountMinors.isEmpty) {
              return base & textHit;
            }
            return base &
                (textHit | t.amountMinor.isIn(amountMinors));
          })
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .get();
    return rows;
  }'''

    new = '''  /// Bill search: optional keyword (note / merchant / amount) plus filters.
  ///
  /// Keyword may be empty when at least one filter is set (type / category /
  /// account / date range). Account filter matches [accountId] or [toAccountId].
  Future<List<Transaction>> searchTransactions(
    String ledgerId,
    String query, {
    String? type,
    String? categoryId,
    String? accountId,
    int? startMs,
    int? endMs,
    int limit = 100,
  }) async {
    final q = query.trim();
    final hasFilter = type != null ||
        categoryId != null ||
        accountId != null ||
        startMs != null ||
        endMs != null;
    if (q.isEmpty && !hasFilter) return const [];

    final pattern = q.isEmpty ? null : '%${q.toLowerCase()}%';
    final amountMinors =
        q.isEmpty ? const <int>[] : _amountMinorCandidates(q);

    final rows = await (select(transactions)
          ..where((t) {
            Expression<bool> pred =
                t.ledgerId.equals(ledgerId) & t.deletedAt.isNull();

            if (type != null) {
              pred = pred & t.type.equals(type);
            }
            if (categoryId != null) {
              pred = pred & t.categoryId.equals(categoryId);
            }
            if (accountId != null) {
              pred = pred &
                  (t.accountId.equals(accountId) |
                      t.toAccountId.equals(accountId));
            }
            if (startMs != null) {
              pred = pred & t.happenAt.isBiggerOrEqualValue(startMs);
            }
            if (endMs != null) {
              pred = pred & t.happenAt.isSmallerThanValue(endMs);
            }

            if (pattern != null) {
              Expression<bool> textHit = t.merchant.lower().like(pattern) |
                  t.note.lower().like(pattern);
              if (amountMinors.isEmpty) {
                pred = pred & textHit;
              } else {
                pred = pred & (textHit | t.amountMinor.isIn(amountMinors));
              }
            }
            return pred;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .get();
    return rows;
  }'''

    if "String? type," in text and "hasFilter" in text:
        print("db already patched")
        return
    if old not in text:
        # try softer match
        m = re.search(
            r"  /// P2 bill search:.*?return rows;\n  }",
            text,
            flags=re.S,
        )
        if not m:
            raise SystemExit("searchTransactions block not found")
        text = text[: m.start()] + new + text[m.end() :]
    else:
        text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    print("patched", path)

def patch_pubspec():
    path = ROOT / "pubspec.yaml"
    text = path.read_text(encoding="utf-8")
    if "speech_to_text:" in text:
        print("pubspec already has speech_to_text")
        return
    needle = "  home_widget: 0.10.0\n"
    if needle not in text:
        raise SystemExit("pubspec anchor missing")
    text = text.replace(
        needle,
        needle + "  speech_to_text: ^7.3.0\n",
        1,
    )
    path.write_text(text, encoding="utf-8", newline="\n")
    print("patched pubspec")

def patch_android_manifest():
    path = ROOT / r"android\app\src\main\AndroidManifest.xml"
    text = path.read_text(encoding="utf-8")
    if "RECORD_AUDIO" in text:
        print("AndroidManifest already has RECORD_AUDIO")
        return
    needle = '    <uses-permission android:name="android.permission.INTERNET" />\n'
    if needle not in text:
        raise SystemExit("AndroidManifest anchor missing")
    text = text.replace(
        needle,
        needle
        + '    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n',
        1,
    )
    # Speech recognition query for Android 11+
    if "RecognitionService" not in text:
        queries = """    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>"""
        new_queries = """    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>"""
        if queries in text:
            text = text.replace(queries, new_queries, 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    print("patched AndroidManifest")

def patch_ios_plist():
    path = ROOT / r"ios\Runner\Info.plist"
    text = path.read_text(encoding="utf-8")
    if "NSMicrophoneUsageDescription" in text:
        print("Info.plist already has mic usage")
        return
    # Insert before closing dict of root — after FaceID if present
    insert = '''	<key>NSMicrophoneUsageDescription</key>
	<string>用于本地语音填单：将说话内容识别为文字后预填记账字段，音频不上传 Centli 服务器。</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>用于本地语音填单：在设备上把语音转成文字并走现有智能填单规则，不经 Centli 云端。</string>
'''
    if "NSFaceIDUsageDescription" in text:
        # insert after FaceID string value line
        m = re.search(
            r"(<key>NSFaceIDUsageDescription</key>\s*<string>.*?</string>\s*)",
            text,
            flags=re.S,
        )
        if m:
            text = text[: m.end()] + insert + text[m.end() :]
        else:
            text = text.replace("</dict>\n</plist>", insert + "</dict>\n</plist>", 1)
    else:
        text = text.replace("</dict>\n</plist>", insert + "</dict>\n</plist>", 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    print("patched Info.plist")

def patch_bookkeeping():
    path = ROOT / r"lib\features\ledger\bookkeeping_sheet.dart"
    text = path.read_text(encoding="utf-8")

    if "local_speech.dart" not in text:
        text = text.replace(
            "import 'ai_text_fill.dart';\n",
            "import 'ai_text_fill.dart';\nimport 'local_speech.dart';\n",
            1,
        )

    if "_speech =" not in text:
        text = text.replace(
            "  final _aiTextCtrl = TextEditingController();\n"
            "  bool _aiExpanded = false;\n"
            "  int _fieldEpoch = 0;\n",
            "  final _aiTextCtrl = TextEditingController();\n"
            "  bool _aiExpanded = false;\n"
            "  int _fieldEpoch = 0;\n"
            "  final _speech = LocalSpeechService();\n"
            "  var _speechListening = false;\n"
            "  var _speechBusy = false;\n",
            1,
        )

    if "_stopSpeech" not in text:
        # dispose: cancel speech
        text = text.replace(
            "    _aiTextCtrl.dispose();\n    super.dispose();",
            "    _aiTextCtrl.dispose();\n"
            "    _speech.cancel();\n"
            "    super.dispose();",
            1,
        )

    voice_methods = r'''
  Future<void> _toggleVoiceFill() async {
    if (_speechListening) {
      await _stopSpeech();
      return;
    }
    if (_speechBusy) return;
    setState(() => _speechBusy = true);
    try {
      final ok = await _speech.ensureReady();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u5f53\u524d\u8bbe\u5907\u4e0d\u652f\u6301\u8bed\u97f3\u8bc6\u522b\uff0c\u8bf7\u6539\u7528\u6587\u5b57\u8bdd\u672f',
            ),
          ),
        );
        return;
      }
      setState(() {
        _aiExpanded = true;
        _speechListening = true;
      });
      await _speech.start(
        onResult: (r) {
          if (!mounted) return;
          setState(() {
            _aiTextCtrl.text = r.text;
            _aiTextCtrl.selection = TextSelection.collapsed(
              offset: _aiTextCtrl.text.length,
            );
          });
          if (r.finalResult && r.text.trim().isNotEmpty) {
            _stopSpeech().then((_) {
              if (mounted) _applyAiTextFill();
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _speechListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u8bed\u97f3\u8bc6\u522b\u5931\u8d25: $e')),
      );
    } finally {
      if (mounted) setState(() => _speechBusy = false);
    }
  }

  Future<void> _stopSpeech() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _speechListening = false);
    } else {
      _speechListening = false;
    }
  }

'''

    if "_toggleVoiceFill" not in text:
        # insert before _applyAiTextFill
        anchor = "  Future<void> _applyAiTextFill() async {"
        if anchor not in text:
            raise SystemExit("applyAiTextFill anchor missing")
        text = text.replace(anchor, voice_methods + anchor, 1)

    # UI: mic button next to 填入
    if "Icons.mic" not in text:
        old_btn = '''                            FilledButton(
                              onPressed: _saving ? null : _applyAiTextFill,
                              child: const Text('填入'),
                            ),'''
        # file may have unicode 填入
        old_btn2 = '''                            FilledButton(
                              onPressed: _saving ? null : _applyAiTextFill,
                              child: const Text('\u586b\u5165'),
                            ),'''
        new_btns = '''                            IconButton.filledTonal(
                              tooltip: _speechListening
                                  ? '\u505c\u6b62\u5f55\u97f3'
                                  : '\u8bed\u97f3\u586b\u5355',
                              onPressed: _saving ? null : _toggleVoiceFill,
                              icon: Icon(
                                _speechListening ? Icons.mic : Icons.mic_none,
                                color: _speechListening
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: _saving ? null : _applyAiTextFill,
                              child: const Text('\u586b\u5165'),
                            ),'''
        if old_btn in text:
            text = text.replace(old_btn, new_btns, 1)
        elif old_btn2 in text:
            text = text.replace(old_btn2, new_btns, 1)
        else:
            # looser: find FilledButton with _applyAiTextFill after ai text field
            m = re.search(
                r"(\s+)FilledButton\(\s+onPressed: _saving \? null : _applyAiTextFill,\s+child: const Text\([^)]+\),\s+\),",
                text,
            )
            if not m:
                raise SystemExit("fill button not found for mic insert")
            indent = m.group(1)
            replacement = (
                f"{indent}IconButton.filledTonal(\n"
                f"{indent}  tooltip: _speechListening\n"
                f"{indent}      ? '\\u505c\\u6b62\\u5f55\\u97f3'\n"
                f"{indent}      : '\\u8bed\\u97f3\\u586b\\u5355',\n"
                f"{indent}  onPressed: _saving ? null : _toggleVoiceFill,\n"
                f"{indent}  icon: Icon(\n"
                f"{indent}    _speechListening ? Icons.mic : Icons.mic_none,\n"
                f"{indent}    color: _speechListening\n"
                f"{indent}        ? Theme.of(context).colorScheme.error\n"
                f"{indent}        : null,\n"
                f"{indent}  ),\n"
                f"{indent}),\n"
                f"{indent}const SizedBox(width: 4),\n"
                f"{m.group(0)}"
            )
            # Actually group(0) includes leading whitespace of FilledButton - messy.
            # Use simpler approach:
            raise SystemExit("fill button pattern ambiguous; manual check needed")

    # Update subtitle hint
    text = text.replace(
        "'话术预填 · 本地规则'",
        "'话术/语音 · 本地'",
    )
    text = text.replace(
        "'\u8bdd\u672f\u9884\u586b \u00b7 \u672c\u5730\u89c4\u5219'",
        "'\u8bdd\u672f/\u8bed\u97f3 \u00b7 \u672c\u5730'",
    )

    path.write_text(text, encoding="utf-8", newline="\n")
    print("patched bookkeeping_sheet")

def main():
    patch_db()
    patch_pubspec()
    patch_android_manifest()
    patch_ios_plist()
    patch_bookkeeping()
    print("done")

if __name__ == "__main__":
    main()
