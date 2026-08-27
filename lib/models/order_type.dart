/// Whether an order is eaten at the table or packed to go — chosen at
/// checkout by both the customer app and the Kasir. Shared between
/// [PosTransaction]/[TransactionItem] (local Kasir sales) and
/// [CustomerOrder] (the shared Supabase order feed the Chef watches).
enum OrderType { dineIn, takeAway }

const _orderTypeDbValues = {
  OrderType.dineIn: 'dine_in',
  OrderType.takeAway: 'take_away',
};

extension OrderTypeDb on OrderType {
  String get dbValue => _orderTypeDbValues[this]!;

  static OrderType fromDb(String? value) {
    return _orderTypeDbValues.entries
        .firstWhere((e) => e.value == value, orElse: () => const MapEntry(OrderType.dineIn, ''))
        .key;
  }
}

const kOrderTypeLabels = {
  OrderType.dineIn: 'Dine In',
  OrderType.takeAway: 'Take Away',
};
