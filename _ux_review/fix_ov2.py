from pathlib import Path
path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')
# Unique context: end of _pickAccount then build
old = '''    });
  }

  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;'''
new = '''    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;'''
if old not in text:
    raise SystemExit('unique build anchor missing')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('added @override')