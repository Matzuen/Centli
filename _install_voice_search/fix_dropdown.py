# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\search_page.dart")
text = p.read_text(encoding="utf-8")
text2 = text.replace(
'''              DropdownButtonFormField<String?>(
                value: _categoryId,
                isExpanded: true,''',
'''              DropdownButtonFormField<String?>(
                key: ValueKey('cat_${_type}_$_categoryId'),
                initialValue: _categoryId,
                isExpanded: true,''',
1)
text2 = text2.replace(
'''              DropdownButtonFormField<String?>(
                value: _accountId,
                isExpanded: true,''',
'''              DropdownButtonFormField<String?>(
                key: ValueKey('acc_$_accountId'),
                initialValue: _accountId,
                isExpanded: true,''',
1)
if text2 == text:
    raise SystemExit('dropdown replace failed')
p.write_text(text2, encoding='utf-8', newline='\n')
print('dropdowns fixed')
