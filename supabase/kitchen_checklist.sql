-- KaataGo — checklist dapur per menu (run AFTER schema.sql).
--
-- Sebelumnya menyelesaikan pesanan cuma satu tombol: dari "dimasak"
-- langsung "selesai". Pada pesanan berisi lima menu, satu yang terlewat
-- tetap membuat pesanannya tercatat selesai, dan baru ketahuan waktu
-- customer bertanya.
--
-- Sekarang tiap menu dicentang satu per satu. Menyimpan nomor barisnya,
-- bukan productId: satu produk bisa muncul beberapa kali sebagai baris
-- terpisah (nasi goreng pedas dan tidak pedas), jadi productId tidak
-- membedakan keduanya. Urutan `items` tidak pernah berubah setelah
-- pesanan dibuat, sehingga nomor barisnya aman dijadikan penanda.
alter table orders add column if not exists items_done jsonb not null default '[]'::jsonb;

-- Chef sudah punya hak update pada `orders` lewat policy
-- "orders: employees update" (lihat rls_hardening.sql), jadi tidak ada
-- policy baru yang perlu ditambahkan di sini.
