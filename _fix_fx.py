from pathlib import Path
p = Path("lib/data/fx/fx_remote_service.dart")
t = p.read_text(encoding="utf-8")
print(t[:800])
print("====TAIL====")
print(t[-400:])
