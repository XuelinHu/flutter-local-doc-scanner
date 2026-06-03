import 'package:flutter/material.dart';

class SavePdfSheet extends StatefulWidget {
  const SavePdfSheet({
    required this.initialName,
    required this.recentNames,
    super.key,
  });

  final String initialName;
  final List<String> recentNames;

  @override
  State<SavePdfSheet> createState() => _SavePdfSheetState();
}

class _SavePdfSheetState extends State<SavePdfSheet> {
  late final TextEditingController _controller;
  String? _selectedHistoryName;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _selectedHistoryName = widget.recentNames.contains(widget.initialName)
        ? widget.initialName
        : null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '保存 PDF 文档',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: '文档名称',
              hintText: '例如：合同扫描件',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() {
                _selectedHistoryName = null;
              });
            },
          ),
          if (widget.recentNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedHistoryName,
              decoration: const InputDecoration(
                labelText: '选择历史名称',
                border: OutlineInputBorder(),
              ),
              items: widget.recentNames
                  .map(
                    (name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedHistoryName = value;
                  _controller.text = value;
                });
              },
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final name = _controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(name);
              },
              child: const Text('保存并生成'),
            ),
          ),
        ],
      ),
    );
  }
}
