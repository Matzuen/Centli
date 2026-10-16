from pathlib import Path
path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')
for s in ["import 'local_speech.dart';", "Widget build(BuildContext context)", "const Spacer()", "class _Keypad extends StatelessWidget"]:
    print(s[:50], '->', text.find(s))
idx = text.find('padding: const EdgeInsets.symmetric(vertical: 8)')
print('vertical8', idx)
print(repr(text[idx-100:idx+80]))
