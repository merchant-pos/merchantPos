-- Seeds realistic Indonesian F&B categories + products.
-- IMPORTANT: replace 'resto-1' below with YOUR actual resto_id
-- (the same value used in your employees table's resto_id column)
-- before running this in Supabase SQL Editor.
--
-- After running, open the app as Admin/Kasir once — it automatically
-- pulls any new products/categories from Supabase into the local
-- device database (see ProductProvider.pullNewProductsFromFirestore /
-- CategoryProvider.pullNewFromSupabase).

do $$
declare
  v_resto_id text := 'resto-1'; -- <-- change this
begin

insert into categories (id, resto_id, name) values
  (gen_random_uuid()::text, v_resto_id, 'Makanan Utama'),
  (gen_random_uuid()::text, v_resto_id, 'Ayam & Bebek'),
  (gen_random_uuid()::text, v_resto_id, 'Seafood'),
  (gen_random_uuid()::text, v_resto_id, 'Mie & Bakmi'),
  (gen_random_uuid()::text, v_resto_id, 'Cemilan'),
  (gen_random_uuid()::text, v_resto_id, 'Dessert'),
  (gen_random_uuid()::text, v_resto_id, 'Kopi & Teh'),
  (gen_random_uuid()::text, v_resto_id, 'Minuman')
on conflict do nothing;

insert into products (id, resto_id, name, category, price, stock, description) values
  (gen_random_uuid()::text, v_resto_id, 'Nasi Goreng Spesial', 'Makanan Utama', 25000, 20, 'Nasi goreng dengan telur, ayam suwir, dan kerupuk.'),
  (gen_random_uuid()::text, v_resto_id, 'Nasi Uduk Komplit', 'Makanan Utama', 22000, 15, 'Nasi uduk gurih dengan ayam goreng, tempe, dan sambal.'),
  (gen_random_uuid()::text, v_resto_id, 'Nasi Campur Bali', 'Makanan Utama', 28000, 12, 'Nasi dengan lauk pauk khas Bali, ayam sisit, dan sambal matah.'),
  (gen_random_uuid()::text, v_resto_id, 'Gado-Gado', 'Makanan Utama', 20000, 18, 'Sayuran segar dengan siraman bumbu kacang khas.'),
  (gen_random_uuid()::text, v_resto_id, 'Soto Ayam', 'Makanan Utama', 23000, 15, 'Soto ayam kuah bening dengan suwiran ayam dan telur.'),

  (gen_random_uuid()::text, v_resto_id, 'Ayam Geprek Sambal Bawang', 'Ayam & Bebek', 24000, 25, 'Ayam goreng crispy digeprek dengan sambal bawang pedas.'),
  (gen_random_uuid()::text, v_resto_id, 'Ayam Bakar Madu', 'Ayam & Bebek', 27000, 15, 'Ayam bakar dengan bumbu madu manis gurih.'),
  (gen_random_uuid()::text, v_resto_id, 'Bebek Goreng Sambal Ijo', 'Ayam & Bebek', 32000, 10, 'Bebek goreng renyah dengan sambal ijo khas Minang.'),
  (gen_random_uuid()::text, v_resto_id, 'Ayam Penyet', 'Ayam & Bebek', 23000, 18, 'Ayam goreng penyet dengan sambal terasi pedas.'),

  (gen_random_uuid()::text, v_resto_id, 'Cumi Goreng Tepung', 'Seafood', 30000, 12, 'Cumi segar digoreng garing dengan bumbu spesial.'),
  (gen_random_uuid()::text, v_resto_id, 'Udang Saus Padang', 'Seafood', 35000, 10, 'Udang segar dimasak dengan saus padang pedas manis.'),
  (gen_random_uuid()::text, v_resto_id, 'Ikan Bakar Kecap', 'Seafood', 33000, 10, 'Ikan segar dibakar dengan bumbu kecap manis.'),

  (gen_random_uuid()::text, v_resto_id, 'Mie Ayam Bakso', 'Mie & Bakmi', 20000, 20, 'Mie ayam dengan topping bakso dan pangsit.'),
  (gen_random_uuid()::text, v_resto_id, 'Mie Goreng Jawa', 'Mie & Bakmi', 21000, 15, 'Mie goreng dengan bumbu rempah khas Jawa.'),
  (gen_random_uuid()::text, v_resto_id, 'Kwetiau Goreng', 'Mie & Bakmi', 23000, 12, 'Kwetiau goreng dengan telur, ayam, dan sayuran.'),

  (gen_random_uuid()::text, v_resto_id, 'Tahu Isi', 'Cemilan', 10000, 25, 'Tahu goreng isi sayuran, disajikan dengan cabai rawit.'),
  (gen_random_uuid()::text, v_resto_id, 'Pisang Goreng Coklat Keju', 'Cemilan', 15000, 20, 'Pisang goreng crispy dengan topping coklat dan keju.'),
  (gen_random_uuid()::text, v_resto_id, 'Kentang Goreng', 'Cemilan', 15000, 25, 'Kentang goreng renyah dengan saus sambal/mayones.'),
  (gen_random_uuid()::text, v_resto_id, 'Tempe Mendoan', 'Cemilan', 10000, 22, 'Tempe goreng tepung khas Banyumas, gurih dan renyah.'),

  (gen_random_uuid()::text, v_resto_id, 'Es Krim Goreng', 'Dessert', 18000, 12, 'Es krim vanilla dibalut roti crispy, disajikan dingin.'),
  (gen_random_uuid()::text, v_resto_id, 'Puding Coklat', 'Dessert', 12000, 15, 'Puding coklat lembut dengan saus vanilla.'),
  (gen_random_uuid()::text, v_resto_id, 'Klepon', 'Dessert', 10000, 20, 'Klepon isi gula merah dengan taburan kelapa parut.'),

  (gen_random_uuid()::text, v_resto_id, 'Kopi Susu Gula Aren', 'Kopi & Teh', 18000, 30, 'Kopi susu dengan gula aren asli, creamy dan manis.'),
  (gen_random_uuid()::text, v_resto_id, 'Es Teh Manis', 'Kopi & Teh', 8000, 40, 'Teh manis segar disajikan dingin.'),
  (gen_random_uuid()::text, v_resto_id, 'Americano', 'Kopi & Teh', 15000, 25, 'Kopi hitam americano, cocok untuk yang suka rasa kopi murni.'),
  (gen_random_uuid()::text, v_resto_id, 'Matcha Latte', 'Kopi & Teh', 20000, 15, 'Matcha premium dengan susu creamy.'),

  (gen_random_uuid()::text, v_resto_id, 'Es Jeruk Peras', 'Minuman', 12000, 20, 'Jeruk peras segar tanpa pengawet.'),
  (gen_random_uuid()::text, v_resto_id, 'Es Campur', 'Minuman', 17000, 15, 'Es campur dengan buah-buahan segar dan sirup.'),
  (gen_random_uuid()::text, v_resto_id, 'Jus Alpukat', 'Minuman', 16000, 15, 'Jus alpukat creamy dengan coklat.'),
  (gen_random_uuid()::text, v_resto_id, 'Air Mineral', 'Minuman', 5000, 50, 'Air mineral dalam kemasan botol.')
on conflict do nothing;

end $$;
