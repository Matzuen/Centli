from pathlib import Path
path = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart")
text = path.read_text(encoding="utf-8")
i = text.find("_toggleVoiceFill")
print(repr(text[i:i+1200]))
