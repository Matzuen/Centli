from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
start = b.find("if (_type == 'transfer') ...[")
if start < 0:
    raise SystemExit("start missing")
# End after the else account Row/Padding closes - find the pattern after else dropdown
# Look for closing of else Padding: after decoration OutlineInputBorder of account dropdown
marker = "onChanged: (v) => setState(() => _accountId = v),\n                            decoration: const InputDecoration(\n                              isDense: true,\n                              border: OutlineInputBorder(),\n                            ),\n                          ),\n                        ),\n                      ],"
# There may be two - we want the one in the else branch (after start)
idx = b.find(marker, start)
if idx < 0:
    raise SystemExit("end marker missing")
# include the rest of the closing parens for Padding
end_snip = b[idx:idx+250]
print("END SNIP:")
print(repr(end_snip))
# Find how many closing lines after items
# Expected:
#                          ),  # dropdown
#                        ),    # expanded
#                      ],      # children
#                    ),        # row
#                  ),          # padding
end = idx + len(marker)
# consume following "\n                    ),\n                  ),"
extra = b[end:end+40]
print("extra", repr(extra))
if extra.startswith("\n                    ),\n                  ),"):
    end = end + len("\n                    ),\n                  ),")
else:
    # try flexible
    import re
    m = re.match(r"\n\s*\),\n\s*\),", b[end:])
    if not m:
        raise SystemExit("cannot find padding close: " + repr(b[end:end+60]))
    end = end + m.end()

fixed = '''if (_type == 'transfer') ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('\\u8f6c\\u51fa',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('dd-from-$_fieldEpoch-$_type'),
                            initialValue: _accounts.any((a) => a.id == _accountId)
                                ? _accountId
                                : null,
                            items: [
                              for (final a in _accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _accountId = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('\\u8f6c\\u5165',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('dd-to-$_fieldEpoch-$_type'),
                            initialValue: _accounts.any((a) => a.id == _toAccountId)
                                ? _toAccountId
                                : null,
                            items: [
                              for (final a in _accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _toAccountId = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isCrossCurrency)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        '\\u8de8\\u5e01\\uff1a\\u4fdd\\u5b58\\u65f6\\u5c06\\u8be2\\u95ee\\u5bf9\\u65b9\\u91d1\\u989d\\u6216\\u6c47\\u7387',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        const Text('\\u8d26\\u6237'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('dd-acc-$_fieldEpoch-$_type'),
                            initialValue: _accounts.any((a) => a.id == _accountId)
                                ? _accountId
                                : null,
                            items: [
                              for (final a in _accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.name} (${a.currency})'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _accountId = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )'''

# Use actual Unicode escapes that are already in file - the file uses real unicode chars
# Re-read original unicode from nearby
# Better: use the same escapes as currently in file for 转出/转入/账户/跨币

fixed = fixed.encode().decode('unicode_escape') if False else None

# Build with explicit unicode from the corrupted region
zhuanchu = "\u8f6c\u51fa"
zhuanru = "\u8f6c\u5165"
zhanghu = "\u8d26\u6237"
kuabi = "\u8de8\u5e01\uff1a\u4fdd\u5b58\u65f6\u5c06\u8be2\u95ee\u5bf9\u65b9\u91d1\u989d\u6216\u6c47\u7387"

fixed = f'''if (_type == 'transfer') ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('{zhuanchu}',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('dd-from-$_fieldEpoch-$_type'),
                            initialValue: _accounts.any((a) => a.id == _accountId)
                                ? _accountId
                                : null,
                            items: [
                              for (final a in _accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${{a.name}} (${{a.currency}})'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _accountId = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('{zhuanru}',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('dd-to-$_fieldEpoch-$_type'),
                            initialValue: _accounts.any((a) => a.id == _toAccountId)
                                ? _toAccountId
                                : null,
                            items: [
                              for (final a in _accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${{a.name}} (${{a.currency}})'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _toAccountId = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isCrossCurrency)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        '{kuabi}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        const Text('{zhanghu}'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('dd-acc-$_fieldEpoch-$_type'),
                            initialValue: _accounts.any((a) => a.id == _accountId)
                                ? _accountId
                                : null,
                            items: [
                              for (final a in _accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${{a.name}} (${{a.currency}})'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _accountId = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )'''

new_b = b[:start] + fixed + b[end:]
if "KEY_TRANSFER_FROM_PLACEHOLDER" in new_b:
    raise SystemExit("placeholder still present")
Path("lib/features/ledger/bookkeeping_sheet.dart").write_text(new_b, encoding="utf-8", newline="\n")
print("restored transfer/account dropdowns, end-start", end-start, "new len", len(fixed))
