from pathlib import Path
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
path = root / "lib/features/ledger/bookkeeping_sheet.dart"
text = path.read_text(encoding="utf-8")

old = '''    } catch (e) {
      if (!mounted) return;
      setState(() => _speechListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u8bed\u97f3\u8bc6\u522b\u5931\u8d25: $e')),
      );
    }'''

new = '''    } catch (e) {
      if (!mounted) return;
      setState(() => _speechListening = false);
      final detail = _speech.lastError;
      final msg = detail == null || detail.isEmpty
          ? '\u8bed\u97f3\u8bc6\u522b\u5931\u8d25: $e'
          : '\u8bed\u97f3\u8bc6\u522b\u5931\u8d25: $e\n$detail';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }'''

if old not in text:
    # try without unicode escapes - file may have real Chinese
    old2 = """    } catch (e) {
      if (!mounted) return;
      setState(() => _speechListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('语音识别失败: $e')),
      );
    }"""
    if old2 not in text:
        raise SystemExit('catch block not found')
    text = text.replace(old2, new.replace('\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25', '语音识别失败'), 1)
else:
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8", newline="\n")
print("patched bookkeeping_sheet.dart")
