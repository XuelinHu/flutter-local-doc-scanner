class LocalPage<T> {
  const LocalPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.firstItem,
    required this.lastItem,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final int firstItem;
  final int lastItem;

  factory LocalPage.fromList(
    List<T> allItems, {
    required int page,
    required int pageSize,
  }) {
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
    }
    final totalPages = (allItems.length + pageSize - 1) ~/ pageSize;
    final currentPage = totalPages == 0 ? 1 : page.clamp(1, totalPages).toInt();
    final start = (currentPage - 1) * pageSize;
    final end = (start + pageSize).clamp(0, allItems.length).toInt();

    return LocalPage<T>(
      items: List<T>.unmodifiable(allItems.sublist(start, end)),
      page: currentPage,
      pageSize: pageSize,
      total: allItems.length,
      totalPages: totalPages,
      firstItem: allItems.isEmpty ? 0 : start + 1,
      lastItem: end,
    );
  }
}
