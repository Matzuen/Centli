from pathlib import Path
p = Path("lib/features/pending/pending_page.dart").read_text(encoding="utf-8")
i = p.find("kDebugMode")
print(p[i-50:i+500])
print("---parens", p.count("(")-p.count(")"), "braces", p.count("{")-p.count("}"))
