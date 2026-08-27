-- KaataGo — judul notifikasi chat tidak menyebut "pengaduan".
--
-- Jalankan SETELAH support_auto_reply.sql. Aman diulang.
--
-- Notifikasi chat selama ini berjudul "Pengaduan dari Budi". Yang
-- membacanya di layar kunci tidak punya cara tahu itu sebenarnya
-- pertanyaan biasa — dan yang mengirimnya merasa dituduh mengadu
-- padahal cuma bertanya.

create or replace function queue_push_support()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t support_tickets;
  v_nama text;
  v_cuplikan text;
  v_admin record;
  v_chat boolean;
begin
  -- Sapaan otomatis tidak dikabarkan: orang yang baru menekan kirim
  -- sedang menatap layarnya.
  if new.sender_email = 'system:greeting' then
    return new;
  end if;

  select * into t from support_tickets where id = new.ticket_id;
  if t is null then return new; end if;

  v_chat := t.subject = 'Chat dengan KaataGo Admin';

  v_cuplikan := left(regexp_replace(new.body, E'[\n\r]+', ' ', 'g'), 90);

  if new.from_admin then
    insert into push_outbox (resto_id, event, payload) values (
      t.resto_id, 'support_message',
      jsonb_build_object(
        'audience', 'email',
        'email', t.reporter_email,
        'ticket_id', t.id::text,
        'title', case
          when v_chat then 'Balasan KaataGo Admin'
          else 'KaataGo Support — ' || t.subject
        end,
        'body', v_cuplikan
      )
    );
  else
    v_nama := coalesce(nullif(btrim(coalesce(t.reporter_name, '')), ''),
                       split_part(t.reporter_email, '@', 1));

    for v_admin in
      select distinct e.email
      from employees e
      where e.role = 'super_admin'
        and coalesce(e.active, true) = true
        and e.email is not null
    loop
      insert into push_outbox (resto_id, event, payload) values (
        null, 'support_message',
        jsonb_build_object(
          'audience', 'email',
          'email', v_admin.email,
          'ticket_id', t.id::text,
          'title', case
            when v_chat then 'Chat dari ' || v_nama
            else 'Pengaduan dari ' || v_nama
          end,
          'body', v_cuplikan
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select payload ->> 'title', payload ->> 'email', sent_at, error
--   from push_outbox where event = 'support_message'
--   order by created_at desc limit 5;
--
--   -- Siapa saja yang dianggap KaataGo Admin, dan sudah punya perangkat
--   -- terdaftar atau belum:
--   select e.email, d.token is not null as punya_perangkat, d.updated_at
--   from employees e
--   left join device_tokens d on d.email = e.email
--   where e.role = 'super_admin';
