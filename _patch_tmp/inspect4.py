from pathlib import Path
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
# How does first success work - check if auto gets disabled, and NotiTemplateStore
bridge = (root/"lib/platform/notifications/notification_ingest_bridge.dart").read_text(encoding="utf-8")
print(bridge)
print("==== STORE ====")
store = root/"lib/platform/notifications/noti_template_store.dart"
print(store.read_text(encoding="utf-8")[:2500] if store.exists() else "missing")
