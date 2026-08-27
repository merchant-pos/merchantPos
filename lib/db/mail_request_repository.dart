import 'package:supabase_flutter/supabase_flutter.dart';

/// Queues a "send this receipt by email" request. A Supabase Edge
/// Function (supabase/functions/send-receipt-email) watches this table
/// and actually sends the email — writing here just enqueues it, and
/// unlike the earlier Firebase setup, this doesn't need any paid plan to
/// deploy (Supabase Edge Functions are free-tier).
class MailRequestRepository {
  final _client = Supabase.instance.client;

  Future<void> requestReceiptEmail({
    required String toEmail,
    required String orderId,
    required String restoId,
  }) async {
    await _client.from('mail_requests').insert({
      'to_email': toEmail,
      'order_id': orderId,
      'resto_id': restoId,
      'status': 'pending',
    });
  }
}
