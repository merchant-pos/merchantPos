/// Indonesia doesn't observe daylight saving, so WIB is a fixed UTC+7
/// offset year-round. Timestamps that come from Supabase (`created_at`
/// etc.) are UTC — formatting them directly would show the backend's
/// clock instead of Indonesia time. Call [toWib] right before formatting
/// a backend timestamp for display (never store/compare the shifted
/// value — it's for display only, comparisons should stay on the real
/// UTC instant).
extension IndonesiaTime on DateTime {
  DateTime toWib() => toUtc().add(const Duration(hours: 7));
}

/// Nomor pesanan versi pendek, sama dengan yang tercetak di struk.
///
/// Delapan karakter pertama. Cukup untuk membedakan pesanan hari itu,
/// cukup pendek untuk dibacakan orang di depan kasir tanpa salah sebut.
String refOf(String id) =>
    id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
