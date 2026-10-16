from pathlib import Path
bk = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart').read_text(encoding='utf-8')
cp = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\category_picker_sheet.dart').read_text(encoding='utf-8')
print('bookkeeping lines', bk.count(chr(10))+1)
print('category picker lines', cp.count(chr(10))+1)
checks = [
  '_MetaChip(',
  'showCategoryPickerSheet',
  'currencyLabel(_currency)',
  'Alignment.centerRight',
  'Icons.edit_outlined',
  'ChoiceChip(',
  'DropdownButtonFormField',
  '支出' in bk or '\\u652f\\u51fa' in bk,
]
for c in ['_MetaChip(', 'showCategoryPickerSheet', 'currencyLabel(_currency)', 'Alignment.centerRight', 'Icons.edit_outlined']:
    print(c, 'OK' if c in bk else 'MISSING')
print('no ChoiceChip', 'ChoiceChip(' not in bk)
print('no Dropdown', 'DropdownButtonFormField' not in bk)
print('picker 选择分类', '选择分类' in cp)
print('picker left sidebar width', 'width: 96' in cp)