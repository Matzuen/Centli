from pathlib import Path
path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')
old = '''  @override

  Category? _categoryById(String? id) {'''
new = '''  Category? _categoryById(String? id) {'''
if old not in text:
    raise SystemExit('orphan override not found')
text = text.replace(old, new, 1)
old2 = '''  Widget build(BuildContext context) {'''
new2 = '''  @override
  Widget build(BuildContext context) {'''
# only the state's build — first occurrence after helpers
if text.count('  Widget build(BuildContext context) {') < 1:
    raise SystemExit('build not found')
# Avoid double @override
if '  @override\n  Widget build(BuildContext context) {' not in text:
    text = text.replace(old2, new2, 1)

# Remove unused go_router import from bookkeeping (moved to category picker)
# But wait — is go_router still used in bookkeeping? ChoiceChip had context.push — removed.
# Check:
if "context.push" in text or "GoRouter" in text or "context.go" in text:
    print('go_router still used')
else:
    text = text.replace("import 'package:go_router/go_router.dart';\n", '', 1)
    print('removed unused go_router import')

# Fix unnecessary underscores in separatorBuilder
text = text.replace('separatorBuilder: (_, __) =>', 'separatorBuilder: (_, _) =>', 1)

# _fieldEpoch was used by dropdown ValueKeys which we removed. Check usage.
import re
uses = len(re.findall(r'_fieldEpoch', text))
print('_fieldEpoch occurrences', uses)
# If only declaration and ++, remove field and increments carefully — or leave warning.
# User asked analyzer clean on touched files — remove unused field.

path.write_text(text, encoding='utf-8', newline='\n')
print('override fixed')