#!/usr/bin/env bash
#
# Menggabung SELURUH berkas SQL jadi satu, untuk database yang masih
# kosong.
#
# Bedanya dengan gabung_sql.sh: yang itu hanya memuat tambalan sejak
# database KaataGo sudah berdiri, jadi ia mengandaikan tabel dasarnya
# ada. Dijalankan di proyek baru, ia berhenti di baris pertama yang
# menyentuh `employees` — tabel yang tidak pernah ia buat sendiri.
#
# Urutannya bukan abjad melainkan urutan berkas-berkas ini dulu
# benar-benar dijalankan, dibaca dari riwayat git KaataGo. Abjad akan
# menaruh categories.sql sebelum schema.sql, dan yang pertama sudah
# menunjuk tabel yang belum ada.
#
# Aman diulang: tiap berkasnya ditulis idempoten.
set -euo pipefail

AKAR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KELUARAN="$AKAR/supabase/JALANKAN-SEMUA.sql"

# seed_products.sql sengaja tidak ikut.
#
# Isinya menu contoh untuk resto bernama 'resto-1', lengkap dengan
# catatan "<-- change this" di dalamnya. Di database kosong ia gagal —
# restonya tidak ada — dan kalau restonya dibuat lebih dulu, yang
# masuk adalah delapan kategori dan puluhan menu karangan ke dalam
# katalog merchant sungguhan.
#
# Jalankan sendiri kalau memang butuh data contoh, setelah mengganti
# resto_id-nya.
FILES=(
  schema.sql
  functions.sql
  categories.sql
  cron.sql
  product_level_groups.sql
  product_photo_desc.sql
  restaurant_category.sql
  rls_hardening.sql
  super_admin.sql
  finance.sql
  customer_browse_resto.sql
  expense_gl_accounts.sql
  order_type.sql
  employee_name_nip.sql
  restaurant_active.sql
  mark_order_paid.sql
  order_customer_name.sql
  settings_finance_access.sql
  backfill_journal.sql
  claim_guest_orders.sql
  expense_receipt.sql
  gl_journal.sql
  petty_cash.sql
  journal_integrity.sql
  kasir_balance_access.sql
  order_cashier_name.sql
  orders_gl_code.sql
  petty_cash_journal.sql
  rejournal.sql
  restaurant_logo.sql
  restaurant_phone.sql
  table_number_text.sql
  tax_and_service.sql
  tax_rates_finance.sql
  cash_deposit.sql
  kitchen_checklist.sql
  owner_multi_resto.sql
  rilis_setor_petty_inbox.sql
  employee_surrogate_key.sql
  promo_banner.sql
  customer_cash_payment.sql
  push_notifications.sql
  announcement_categories.sql
  fix_device_tokens_rls.sql
  push_trigger_pg_net.sql
  payment_gateway.sql
  gateway_settlement.sql
  resto_payment_accounts.sql
  announcement_push.sql
  cash_payment_expiry.sql
  counter_charge.sql
  gateway_account_super_admin.sql
  level_groups.sql
  product_out_of_stock.sql
  resto_order_types.sql
  default_gl_accounts.sql
  discounts.sql
  promo_banner_period.sql
  announcement_audience.sql
  kasir_journal_read.sql
  cancel_order.sql
  settled_at_counter.sql
  discount_min_qty.sql
  discount_product_rules.sql
  billing.sql
  billing_va.sql
  platform_finance.sql
  resto_soft_delete.sql
  billing_discount_apply.sql
  billing_journal_gross.sql
  gl_discount_backfill.sql
  platform_gl_renumber.sql
  product_toppings.sql
  vouchers.sql
  voucher_payouts.sql
  billing_due_day.sql
  market_report.sql
  voucher_announcement.sql
  voucher_manage.sql
  balance_topup.sql
  voucher_new_customer.sql
  qris_receipt_fields.sql
  customer_display.sql
  order_number.sql
  resto_facilities.sql
  merchant_reviews.sql
  review_prompt.sql
  order_cancel_kitchen.sql
  cashier_shift.sql
  product_badges_reviews.sql
  product_review_per_order.sql
  cash_variance.sql
  merchant_report.sql
  shift_opening_check.sql
  support_tickets.sql
  support_push.sql
  support_auto_reply.sql
  support_chat_rules.sql
  support_pesan_kembar.sql
  support_push_wording.sql
)

{
  echo "-- MerchantPOS — seluruh skema, dari database kosong."
  echo "--"
  echo "-- Dibangkitkan scripts/gabung_sql_lengkap.sh. Jangan disunting"
  echo "-- langsung; sunting berkas sumbernya di supabase/ lalu jalankan"
  echo "-- skripnya lagi."
  echo "--"
  echo "-- JANGAN dijalankan di proyek Supabase KaataGo."
  echo ""
} > "$KELUARAN"

n=0
for f in "${FILES[@]}"; do
  sumber="$AKAR/supabase/$f"
  if [[ ! -f "$sumber" ]]; then
    echo "hilang: $f" >&2
    exit 1
  fi
  n=$((n + 1))
  {
    echo ""
    echo "-- ═══════════════════════════════════════════════════════════"
    echo "-- $n. $f"
    echo "-- ═══════════════════════════════════════════════════════════"
    echo ""
    cat "$sumber"
    echo ""
  } >> "$KELUARAN"
done

echo "dibuat: $KELUARAN ($(wc -l < "$KELUARAN" | tr -d ' ') baris, $n berkas)"
