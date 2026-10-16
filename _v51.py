from pathlib import Path
io = Path("lib/platform/notifications/notification_listener_io.dart").read_text(encoding="utf-8")
print("count setMethodCallHandler", io.count("setMethodCallHandler"))
idx=0
while True:
    i=io.find("setMethodCallHandler", idx)
    if i<0: break
    print("---", i)
    print(io[i-80:i+120])
    idx=i+1
print("bindPendingIntake early return supported?", "if (!supported) return;" in io[io.find("bindPendingIntake"):io.find("bindPendingIntake")+300])
print(io[io.find("bindPendingIntake"):io.find("bindPendingIntake")+400])
