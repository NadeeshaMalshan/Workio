import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shows a confirmation dialog matching the frontend worker portal when toggling online/offline status.
/// Returns true if the user confirmed the change, or false if cancelled or dismissed.
Future<bool> showAvailabilityConfirmDialog(
  BuildContext context, {
  required bool targetOnline,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: targetOnline ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              targetOnline ? 'Go Online?' : 'Go Offline?',
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: GoogleFonts.dmSans(
                  fontSize: 14.5,
                  height: 1.55,
                  color: const Color(0xFF475569),
                ),
                children: [
                  const TextSpan(text: 'Are you sure you want to switch your status to '),
                  TextSpan(
                    text: targetOnline ? 'Available for Work' : 'Currently Offline',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              targetOnline
                  ? 'You will be visible to residents in search results and eligible to receive new hire requests.'
                  : "You will be temporarily hidden from search results and won't receive new booking requests until you turn it back on.",
              style: GoogleFonts.dmSans(
                fontSize: 13.5,
                height: 1.5,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              foregroundColor: const Color(0xFF64748B),
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: targetOnline ? const Color(0xFF16A34A) : Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              targetOnline ? 'Yes, Go Online' : 'Yes, Go Offline',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );

  return result == true;
}
