from pathlib import Path
lines = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart').read_text(encoding='utf-8').splitlines()
for i in range(1065, 1080):
    print(f'{i+1}: {repr(lines[i])}')