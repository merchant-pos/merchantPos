-- KaataGo — bagian 62: pesan kembar di dalam satu percakapan.
-- Jalankan SETELAH bagian 61. Aman diulang.

-- KaataGo — pesan kembar di dalam satu percakapan.
--
-- Jalankan SETELAH support_chat_rules.sql. Aman diulang.
--
-- Bagian 61 menjaga TIKET tidak lahir dua kali. Ia tidak menjaga
-- PESAN — dan percakapan yang sudah terlanjur berisi pesan ganda tetap
-- berisi pesan ganda selamanya, karena chat bebas memang sengaja
-- memakai percakapan yang sama terus-menerus.
--
-- Dua hal dikerjakan di sini: membersihkan yang sudah telanjur, dan
-- membuat pengulangannya mustahil.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Membersihkan yang sudah telanjur
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang dibuang hanya yang benar-benar kembar: percakapan yang sama,
-- pengirim yang sama, isi yang sama persis, dalam detik yang sama. Yang
-- tertua disimpan.
--
-- Batas satu detik sengaja sempit. Orang yang mengirim "iya" dua kali
-- berjarak beberapa detik memang mengirimnya dua kali, dan menghapus
-- yang kedua berarti menghapus ucapan yang benar-benar diucapkan.
with kembar as (
  select id,
         row_number() over (
           partition by ticket_id, sender_email, body,
                        date_trunc('second', timezone('UTC', created_at))
           order by created_at
         ) as urutan
  from support_messages
)
delete from support_messages
where id in (select id from kembar where urutan > 1);

-- ─────────────────────────────────────────────────────────────────────
-- Membuat pengulangannya mustahil
-- ─────────────────────────────────────────────────────────────────────
--
-- Bukan lagi bergantung pada urutan pemeriksaan di aplikasi maupun di
-- fungsi. Basis data yang menolak barisnya, dan penolakan itu berlaku
-- untuk semua jalan masuk sekaligus — tombol yang diketuk dua kali,
-- permintaan yang diulang jaringan, maupun proses yang mati lalu
-- mencoba lagi.
--
-- `timezone('UTC', ...)` dipakai supaya ekspresinya immutable; Postgres
-- menolak mengindeks `date_trunc` atas timestamptz apa adanya, karena
-- hasilnya bergantung zona waktu sesi.
create unique index if not exists support_messages_tanpa_kembar
  on support_messages (
    ticket_id,
    sender_email,
    md5(body),
    date_trunc('second', timezone('UTC', created_at)));

-- Sapaan otomatis paling banyak satu per percakapan.
--
-- Terpisah dari indeks di atas karena alasannya berbeda: yang ini bukan
-- soal ketukan ganda, melainkan soal sapaan yang tidak boleh muncul lagi
-- setiap kali fungsinya dijalankan ulang.
create unique index if not exists support_messages_satu_sapaan
  on support_messages (ticket_id)
  where sender_email = 'system:greeting';

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Harus kosong:
--   select ticket_id, sender_email, body, count(*)
--   from support_messages
--   group by ticket_id, sender_email, body,
--            date_trunc('second', timezone('UTC', created_at))
--   having count(*) > 1;
--
--   -- Percakapan yang baru dibuat harus berisi tepat dua pesan:
--   select t.subject, count(m.id) as pesan
--   from support_tickets t join support_messages m on m.ticket_id = t.id
--   group by t.id, t.subject
--   order by max(m.created_at) desc limit 5;
