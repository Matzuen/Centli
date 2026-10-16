# -*- coding: utf-8 -*-
from pathlib import Path
path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')
old = '''              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                ),
              ),'''
new = '''              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                ),
              ),'''
if old not in text:
    raise SystemExit('Flexible label block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('MetaChip constraint fixed')