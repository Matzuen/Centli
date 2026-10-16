from pathlib import Path
text = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart').read_text(encoding='utf-8')
lines = text.splitlines()
for i in range(1000, 1100):
    print(f'{i+1}: {lines[i]}')
print('---')
# brace balance rough around state class
# find class _BookkeepingSheetState and next top-level class
for i,l in enumerate(lines):
    if l.startswith('class '):
        print(i+1, l)