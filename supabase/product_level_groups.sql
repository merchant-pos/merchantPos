-- Adds the "level/varian" tagging to products (e.g. which products offer
-- a spice level, sugar level, etc.), plus optional per-option price
-- deltas (e.g. "Ukuran: Large" adds Rp 5.000 on top of the base price).
-- Group/option names themselves are hardcoded in the app (kLevelGroups) —
-- only which groups apply, and each option's price delta, are stored here.
alter table products add column if not exists level_groups text;
alter table products add column if not exists level_prices text; -- JSON: {"Ukuran": {"Regular": 0, "Large": 5000}}
