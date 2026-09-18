import 'package:flutter/material.dart';

import '../../domain/waypoint_note_field.dart';
import '../../domain/waypoint_test_action.dart';

Future<void> showWaypointNoteSheet(
  BuildContext context, {
  required WaypointTestAction action,
  required VoidCallback onSaved,
}) {
  final field = action.noteField;
  if (field == null) {
    return Future<void>.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        WaypointNoteSheet(action: action, field: field, onSaved: onSaved),
  );
}

final class WaypointNoteSheet extends StatefulWidget {
  const WaypointNoteSheet({
    super.key,
    required this.action,
    required this.field,
    required this.onSaved,
  });

  final WaypointTestAction action;
  final WaypointNoteField field;
  final VoidCallback onSaved;

  @override
  State<WaypointNoteSheet> createState() => _WaypointNoteSheetState();
}

final class _WaypointNoteSheetState extends State<WaypointNoteSheet> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.action.title,
              key: const ValueKey<String>('waypoint-note-title'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.action.subtitle,
              key: const ValueKey<String>('waypoint-note-subtitle'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            Text(
              widget.field.label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey<String>('waypoint-note-field'),
              controller: _noteController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: widget.field.placeholder,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('waypoint-note-save'),
                onPressed: _noteController.text.trim().isEmpty
                    ? null
                    : () {
                        widget.onSaved();
                        Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(widget.action.submitLabel),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
