import 'package:flutter_local_doc_scanner/core/utils/local_pagination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'returns stable non-overlapping pages and clamps an out-of-range page',
    () {
      final records = List<int>.generate(25, (index) => index + 1);

      final first = LocalPage<int>.fromList(records, page: 1, pageSize: 10);
      final second = LocalPage<int>.fromList(records, page: 2, pageSize: 10);
      final last = LocalPage<int>.fromList(records, page: 99, pageSize: 10);

      expect(first.items, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(second.items, [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
      expect(last.items, [21, 22, 23, 24, 25]);
      expect(last.page, 3);
      expect(last.firstItem, 21);
      expect(last.lastItem, 25);
      expect(last.totalPages, 3);
    },
  );

  test('represents an empty result without an invalid page range', () {
    final page = LocalPage<String>.fromList(const [], page: 4, pageSize: 10);

    expect(page.items, isEmpty);
    expect(page.page, 1);
    expect(page.totalPages, 0);
    expect(page.firstItem, 0);
    expect(page.lastItem, 0);
  });
}
