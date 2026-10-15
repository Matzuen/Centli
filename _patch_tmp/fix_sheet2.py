from pathlib import Path
path = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart")
text = path.read_text(encoding="utf-8")
old = """    } catch (e) {
      if (!mounted) return;
      setState(() => _speechListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e')),
      );
    }"""
# In the file the content is literally \u8bed... (one backslash)
old = """    } catch (e) {
      if (!mounted) return;
      setState(() => _speechListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e')),
      );
    }"""
# Fix: construct with real single-backslash unicode escapes as in Dart source
old = (
    "    } catch (e) {\n"
    "      if (!mounted) return;\n"
    "      setState(() => _speechListening = false);\n"
    "      ScaffoldMessenger.of(context).showSnackBar(\n"
    "        SnackBar(content: Text('\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e')),\n"
    "      );\n"
    "    }"
)
# Wait - in Python '\\u8bed' is backslash + u8bed. Good.
print("found", old in text)
new = (
    "    } catch (e) {\n"
    "      if (!mounted) return;\n"
    "      setState(() => _speechListening = false);\n"
    "      final detail = _speech.lastError;\n"
    "      final msg = detail == null || detail.isEmpty\n"
    "          ? '\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e'\n"
    "          : '\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e\\n$detail';\n"
    "      ScaffoldMessenger.of(context).showSnackBar(\n"
    "        SnackBar(content: Text(msg)),\n"
    "      );\n"
    "    }"
)
if old not in text:
    raise SystemExit('not found')
path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
print("patched sheet")
