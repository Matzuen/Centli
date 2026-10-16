from pathlib import Path
path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')
text2 = text.replace('  int _fieldEpoch = 0;\n', '')
text2 = text2.replace('        _fieldEpoch++;\n', '')
if text2 == text:
    raise SystemExit('fieldEpoch not removed')
path.write_text(text2, encoding='utf-8', newline='\n')
print('removed _fieldEpoch')