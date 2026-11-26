import 'dart:convert';

import '../models/scan_card.dart';

/// Builds the CRM-ready JSON payload for a batch of staged cards.
class BatchExport {
  const BatchExport();

  static const String schemaId = 'helloscan.contact-batch.v1';

  Map<String, dynamic> buildPayload(
    List<ScanCard> cards, {
    DateTime? exportedAt,
  }) {
    final timestamp = (exportedAt ?? DateTime.now()).toUtc();
    return {
      'schema': schemaId,
      'exported_at': timestamp.toIso8601String(),
      'total': cards.length,
      'contacts': cards.map((card) => card.toJson()).toList(),
    };
  }

  String encode(List<ScanCard> cards, {DateTime? exportedAt}) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(buildPayload(cards, exportedAt: exportedAt));
  }
}
