# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\local_speech.dart")
text = p.read_text(encoding="utf-8")
old = '''    await _plugin.listen(
      onResult: (r) {
        onResult(
          LocalSpeechResult(
            text: r.recognizedWords,
            finalResult: r.finalResult,
          ),
        );
      },
      localeId: locale,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        partialResults: true,
      ),
    );'''
new = '''    await _plugin.listen(
      onResult: (r) {
        onResult(
          LocalSpeechResult(
            text: r.recognizedWords,
            finalResult: r.finalResult,
          ),
        );
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        partialResults: true,
        // Prefer on-device recognition; fails if the OS has no offline pack.
        onDevice: true,
        localeId: locale,
      ),
    );'''
if old not in text:
    raise SystemExit('listen block not found')
p.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('updated onDevice')
