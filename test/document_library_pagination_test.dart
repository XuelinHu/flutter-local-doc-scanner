import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_doc_scanner/core/services/pdf_library_service.dart';
import 'package:flutter_local_doc_scanner/features/home/home_page.dart';
import 'package:flutter_local_doc_scanner/features/home/saved_pdf_card.dart';
import 'package:flutter_local_doc_scanner/models/pdf_document_record.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPdfLibrary extends PdfLibraryService {
  _MemoryPdfLibrary(this.data);

  final PdfLibraryData data;

  @override
  Future<PdfLibraryData> loadLibrary() async => data;
}

void main() {
  testWidgets('document library paginates and search resets to first page', (
    tester,
  ) async {
    final documents = List<PdfDocumentRecord>.generate(
      25,
      (index) => PdfDocumentRecord(
        id: 'doc-${index + 1}',
        name: '文档${(index + 1).toString().padLeft(2, '0')}',
        filePath: 'missing-${index + 1}.pdf',
        pageCount: 1,
        createdAt: DateTime.utc(2026, 1, index + 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          cameras: const <CameraDescription>[],
          pdfLibraryService: _MemoryPdfLibrary(
            PdfLibraryData(documents: documents, recentNames: const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('文档'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('文档01'), findsOneWidget);
    expect(find.text('文档11'), findsNothing);

    await tester.scrollUntilVisible(
      find.byTooltip('下一页'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, 2000));
    await tester.pumpAndSettle();

    expect(find.text('文档11'), findsOneWidget);
    expect(find.text('文档21'), findsNothing);
    await tester.scrollUntilVisible(
      find.byTooltip('下一页'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('11-20 条，共 25 条'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '文档25');
    await tester.pumpAndSettle();
    expect(find.byType(SavedPdfCard), findsOneWidget);
    expect(
      tester.widget<SavedPdfCard>(find.byType(SavedPdfCard)).document.name,
      '文档25',
    );
    expect(find.text('1/1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
