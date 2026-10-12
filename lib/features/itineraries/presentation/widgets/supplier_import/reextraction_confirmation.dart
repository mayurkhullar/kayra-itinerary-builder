import 'package:flutter/material.dart';

class ReextractionConfirmation extends StatefulWidget {
  const ReextractionConfirmation({super.key, required this.hasReviewChanges});
  final bool hasReviewChanges;

  @override
  State<ReextractionConfirmation> createState() => _ConfirmationState();
}

class _ConfirmationState extends State<ReextractionConfirmation> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Extract supplier itinerary again?'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This creates a new extraction from the same uploaded supplier files. Your current extraction will remain unchanged.',
        ),
        if (widget.hasReviewChanges) ...[
          const SizedBox(height: 16),
          const Text(
            'Changes made during this review will not be copied to the new extraction.',
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        autofocus: true,
        onPressed: _submitted ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submitted
            ? null
            : () {
                if (_submitted) return;
                setState(() => _submitted = true);
                Navigator.of(context).pop(true);
              },
        child: const Text('Extract again'),
      ),
    ],
  );
}
