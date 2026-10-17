import 'package:centli/core/utils/note_compose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('composeNote', () {
    test('both null → null', () {
      expect(composeNote(merchant: null, note: null), isNull);
    });

    test('merchant only', () {
      expect(composeNote(merchant: '星巴克', note: null), '星巴克');
    });

    test('note only', () {
      expect(composeNote(merchant: null, note: '午饭'), '午饭');
    });

    test('both → merchant · note', () {
      expect(composeNote(merchant: '星巴克', note: '午饭'), '星巴克 · 午饭');
    });

    test('blank strings treated as null', () {
      expect(composeNote(merchant: '  ', note: '  '), isNull);
      expect(composeNote(merchant: ' 星巴克 ', note: ' '), '星巴克');
      expect(composeNote(merchant: '', note: '午饭'), '午饭');
    });
  });
}
