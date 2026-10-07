-- ====================================================================
-- DHWANI (ಧ್ವನಿ) - SUPABASE SCHEMA & SEED DATA (KARNATAKA STATEWIDE)
-- "Your voice. Your shop."
-- Micro-Commerce Platform for Women & Micro-Entrepreneurs across Karnataka
-- ====================================================================

-- 1. EXTENSIONS
create extension if not exists "uuid-ossp";

-- 2. TABLES

-- Sellers Table
create table if not exists public.sellers (
    id uuid primary key default uuid_generate_v4(),
    phone text not null unique,
    name text not null,
    shop_name text not null,
    slug text not null unique,
    district text not null default 'Hubballi-Dharwad',
    ward text not null, -- Locality, Area or Ward
    language text not null default 'kn-IN',
    upi_id text not null,
    category text not null default 'Sweets & Snacks',
    theme jsonb not null default '{"color": "#1F5E4B", "tagline": "Handcrafted with passion"}'::jsonb,
    avatar_url text,
    bio text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Listings / Products Table
create table if not exists public.listings (
    id uuid primary key default uuid_generate_v4(),
    seller_id uuid not null references public.sellers(id) on delete cascade,
    title text not null,
    price numeric(10, 2) not null check (price >= 0),
    unit text not null default 'packet',
    category text not null default 'General',
    description_local text,
    description_en text,
    image_url text,
    available boolean not null default true,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Orders Table
create table if not exists public.orders (
    id uuid primary key default uuid_generate_v4(),
    seller_id uuid not null references public.sellers(id) on delete cascade,
    listing_id uuid references public.listings(id) on delete set null,
    items jsonb not null default '[]'::jsonb, -- Array of items: [{title, price, qty, unit}]
    buyer_name text not null,
    buyer_phone text not null,
    qty integer not null default 1 check (qty > 0),
    amount numeric(10, 2) not null check (amount >= 0),
    status text not null default 'new' check (status in ('new', 'paid', 'ready', 'delivered', 'cancelled')),
    fulfilment text not null default 'pickup' check (fulfilment in ('pickup', 'rider')),
    delivery_address text,
    notes text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 3. INDEXES FOR PERFORMANCE
create index if not exists idx_sellers_slug on public.sellers(slug);
create index if not exists idx_sellers_phone on public.sellers(phone);
create index if not exists idx_sellers_district on public.sellers(district);
create index if not exists idx_listings_seller on public.listings(seller_id);
create index if not exists idx_listings_category on public.listings(category);
create index if not exists idx_orders_seller on public.orders(seller_id);
create index if not exists idx_orders_created on public.orders(created_at desc);

-- 4. ROW LEVEL SECURITY (RLS)
alter table public.sellers enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;

-- Drop existing policies if any
drop policy if exists "Public read access for sellers" on public.sellers;
drop policy if exists "Public insert/update for sellers" on public.sellers;
drop policy if exists "Public read access for listings" on public.listings;
drop policy if exists "Public insert/update/delete for listings" on public.listings;
drop policy if exists "Public read access for orders" on public.orders;
drop policy if exists "Public insert/update for orders" on public.orders;

-- Sellers policies
create policy "Public read access for sellers"
    on public.sellers for select
    using (true);

create policy "Public insert/update for sellers"
    on public.sellers for all
    using (true)
    with check (true);

-- Listings policies
create policy "Public read access for listings"
    on public.listings for select
    using (true);

create policy "Public insert/update/delete for listings"
    on public.listings for all
    using (true)
    with check (true);

-- Orders policies
create policy "Public read access for orders"
    on public.orders for select
    using (true);

create policy "Public insert/update for orders"
    on public.orders for all
    using (true)
    with check (true);

-- 5. REALTIME REPLICATION
alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.listings;

-- 6. WEEKLY SALES VIEW
create or replace view public.view_seller_weekly_sales as
select
    seller_id,
    date_trunc('week', created_at) as week_start,
    count(id) as order_count,
    sum(amount) as total_amount,
    count(distinct buyer_phone) as unique_buyers
from public.orders
where status != 'cancelled'
group by seller_id, date_trunc('week', created_at)
order by week_start desc;

-- 7. PASSPORT CALCULATION POSTGRES FUNCTION
create or replace function public.get_passport(p_seller_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
    v_seller record;
    v_total_sales numeric := 0;
    v_total_orders integer := 0;
    v_repeat_customers_count integer := 0;
    v_unique_buyers_count integer := 0;
    v_months_active numeric := 1;
    v_avg_monthly_sales numeric := 0;
    v_repeat_rate numeric := 0;
    v_weeks_active integer := 0;
    v_score_active_ratio numeric := 0;
    v_score_volume numeric := 0;
    v_score_repeat numeric := 0;
    v_score_growth numeric := 0;
    v_consistency_score integer := 0;
    v_recent_4w_sales numeric := 0;
    v_prior_4w_sales numeric := 0;
    v_weekly_data jsonb := '[]'::jsonb;
    v_result jsonb;
begin
    -- Get seller info
    select * into v_seller from public.sellers where id = p_seller_id;
    if not found then
        return jsonb_build_object('error', 'Seller not found');
    end if;

    -- Calculate basic metrics
    select
        coalesce(sum(amount), 0),
        count(id),
        coalesce(count(distinct buyer_phone), 0)
    into
        v_total_sales,
        v_total_orders,
        v_unique_buyers_count
    from public.orders
    where seller_id = p_seller_id and status in ('paid', 'ready', 'delivered');

    -- Calculate repeat customers (buyers with > 1 completed order)
    select count(*)
    into v_repeat_customers_count
    from (
        select buyer_phone
        from public.orders
        where seller_id = p_seller_id and status in ('paid', 'ready', 'delivered')
        group by buyer_phone
        having count(id) > 1
    ) sub;

    -- Months active calculation
    select greatest(1, ceil(extract(epoch from (now() - created_at)) / (30 * 86400))::numeric)
    into v_months_active
    from public.sellers
    where id = p_seller_id;

    v_avg_monthly_sales := round(v_total_sales / v_months_active, 2);

    if v_unique_buyers_count > 0 then
        v_repeat_rate := round((v_repeat_customers_count::numeric / v_unique_buyers_count::numeric) * 100, 1);
    else
        v_repeat_rate := 0;
    end if;

    -- 12-week trend query
    with weeks as (
        select generate_series(
            date_trunc('week', now()) - interval '11 weeks',
            date_trunc('week', now()),
            interval '1 week'
        ) as w_start
    ),
    weekly_agg as (
        select
            w.w_start,
            coalesce(sum(o.amount), 0) as week_sales,
            count(o.id) as week_orders
        from weeks w
        left join public.orders o
            on o.seller_id = p_seller_id
            and o.status in ('paid', 'ready', 'delivered')
            and date_trunc('week', o.created_at) = w.w_start
        group by w.w_start
        order by w.w_start asc
    )
    select
        jsonb_agg(
            jsonb_build_object(
                'week_label', to_char(w_start, 'Mon DD'),
                'sales', week_sales,
                'orders', week_orders
            )
        ),
        count(case when week_sales > 0 then 1 end)
    into v_weekly_data, v_weeks_active
    from weekly_agg;

    -- Growth comparison: recent 4 weeks vs prior 4 weeks
    with weekly_sales as (
        select
            date_trunc('week', created_at) as w_start,
            sum(amount) as sales
        from public.orders
        where seller_id = p_seller_id and status in ('paid', 'ready', 'delivered')
        group by date_trunc('week', created_at)
    )
    select
        coalesce(sum(case when w_start >= date_trunc('week', now()) - interval '3 weeks' then sales end), 0),
        coalesce(sum(case when w_start < date_trunc('week', now()) - interval '3 weeks' and w_start >= date_trunc('week', now()) - interval '7 weeks' then sales end), 0)
    into v_recent_4w_sales, v_prior_4w_sales
    from weekly_sales;

    -- CONSISTENCY SCORE CALCULATION (0-100)
    -- 1. Active-weeks ratio (40%): (weeks_active / 12) * 40
    v_score_active_ratio := (least(v_weeks_active, 12)::numeric / 12.0) * 40.0;

    -- 2. Sales volume capped scale (25%): min(total_sales / 25000, 1.0) * 25
    v_score_volume := least((v_total_sales / 25000.0), 1.0) * 25.0;

    -- 3. Repeat customer rate (20%): (repeat_rate / 100) * 20
    v_score_repeat := (least(v_repeat_rate, 100.0) / 100.0) * 20.0;

    -- 4. Growth trend (15%): recent 4w vs prior 4w
    if v_prior_4w_sales > 0 then
        v_score_growth := least((v_recent_4w_sales / v_prior_4w_sales), 1.5) / 1.5 * 15.0;
    elsif v_recent_4w_sales > 0 then
        v_score_growth := 10.0;
    else
        v_score_growth := 0;
    end if;

    v_consistency_score := round(v_score_active_ratio + v_score_volume + v_score_repeat + v_score_growth);
    if v_consistency_score > 100 then v_consistency_score := 100; end if;
    if v_consistency_score < 0 then v_consistency_score := 0; end if;

    -- Build output payload
    v_result := jsonb_build_object(
        'seller', jsonb_build_object(
            'id', v_seller.id,
            'name', v_seller.name,
            'shop_name', v_seller.shop_name,
            'slug', v_seller.slug,
            'district', v_seller.district,
            'ward', v_seller.ward,
            'phone', v_seller.phone,
            'upi_id', v_seller.upi_id,
            'created_at', v_seller.created_at
        ),
        'metrics', jsonb_build_object(
            'total_sales', v_total_sales,
            'total_orders', v_total_orders,
            'months_active', v_months_active,
            'avg_monthly_sales', v_avg_monthly_sales,
            'repeat_customers_count', v_repeat_customers_count,
            'unique_buyers_count', v_unique_buyers_count,
            'repeat_rate_percent', v_repeat_rate,
            'weeks_active_count', v_weeks_active
        ),
        'consistency_score', jsonb_build_object(
            'total_score', v_consistency_score,
            'breakdown', jsonb_build_object(
                'active_weeks_ratio_points', round(v_score_active_ratio, 1),
                'active_weeks_max', 40,
                'sales_volume_points', round(v_score_volume, 1),
                'sales_volume_max', 25,
                'repeat_customers_points', round(v_score_repeat, 1),
                'repeat_customers_max', 20,
                'growth_trend_points', round(v_score_growth, 1),
                'growth_trend_max', 15
            ),
            'formula', 'Consistency Score = 40% (Active Weeks Ratio) + 25% (Volume Index up to ₹25k) + 20% (Repeat Buyer %) + 15% (Quarterly Growth Momentum)'
        ),
        'weekly_trend', v_weekly_data,
        'generated_at', now()
    );

    return v_result;
end;
$$;

-- 8. SEED DATA: 8 REALISTIC WOMEN ENTREPRENEURS ACROSS KARNATAKA
truncate table public.orders, public.listings, public.sellers cascade;

insert into public.sellers (id, phone, name, shop_name, slug, district, ward, language, upi_id, category, theme, bio)
values
(
    '11111111-1111-1111-1111-111111111111',
    '9845012345',
    'Renuka Patil',
    'Renuka North Karnataka Holige Mane',
    'renuka-holige',
    'Hubballi-Dharwad',
    'Vidyanagar',
    'kn-IN',
    'renukapatil@okhdfcbank',
    'Sweets & Snacks',
    '{"color": "#E8A317", "tagline": "Traditional Belagavi & Hubli Shenga Holige and Ghee Puran Poli"}'::jsonb,
    'Making authentic North Karnataka soft Shenga Holige and Bele Holige using 40-year-old family recipes.'
),
(
    '22222222-2222-2222-2222-222222222222',
    '9480123456',
    'Sunita Kulkarni',
    'Kulkarni Aaji Podi & Masala Kitchen',
    'kulkarni-masala',
    'Belagavi',
    'Tilakwadi',
    'kn-IN',
    'sunitakulkarni@oksbi',
    'Masalas & Podis',
    '{"color": "#C8553D", "tagline": "Hand-ground chutney powders, Shenga Chutney & Rasam Masala"}'::jsonb,
    'Sun-dried, stone-ground traditional Karnataka podis without artificial preservatives.'
),
(
    '33333333-3333-3333-3333-333333333333',
    '9900987654',
    'Shweta Rao',
    'Mysuru Sandalwood & Traditional Silk Crafts',
    'mysuru-crafts',
    'Mysuru',
    'Gokulam',
    'kn-IN',
    'shwetarao@paytm',
    'Handicrafts & Tailoring',
    '{"color": "#7E22CE", "tagline": "Handcrafted sandalwood artefacts and heritage Mysore silk pouches"}'::jsonb,
    'Handcrafted artisanal Mysore silk potlis, fragrant incense, and bridal accessories.'
),
(
    '44444444-4444-4444-4444-444444444444',
    '9731234567',
    'Kavita Bhat',
    'Karavali Coastal Flavours & Cashew Sweets',
    'karavali-bhat',
    'Mangaluru',
    'Kadri',
    'kn-IN',
    'kavitabhat@icici',
    'Sweets & Snacks',
    '{"color": "#D97706", "tagline": "Authentic Coastal Jackfruit Halwa, Cashew Macaroons & Mango Relish"}'::jsonb,
    'Home-made Mangalore cashew snacks, sun-dried jackfruit papads, and traditional coastal sweets.'
),
(
    '55555555-5555-5555-5555-555555555555',
    '9611122334',
    'Savita Hiremath',
    'Savita Jowar Rotti & Ennegai Kendra',
    'savita-rotti',
    'Kalaburagi',
    'Super Market Area',
    'kn-IN',
    'savitahiremath@upi',
    'Tiffin & Meals',
    '{"color": "#1F5E4B", "tagline": "Crisp Kadak Jowar Rotti, Badanekayi Ennegai & Shenga Pudi"}'::jsonb,
    'Traditional North Karnataka thin Jowar Rottis and spicy stuffed brinjal curry.'
),
(
    '66666666-6666-6666-6666-666666666666',
    '9886554433',
    'Nandini Hegde',
    'Malnad Organic Spices & Wild Honey',
    'malnad-organics',
    'Shivamogga',
    'Thirthahalli Road',
    'kn-IN',
    'nandinihegde@axisbank',
    'Organic Produce',
    '{"color": "#15803D", "tagline": "Single-origin Western Ghats Black Pepper, Cardamom & Raw Honey"}'::jsonb,
    'Estate-grown pure spices, Malnad kokum butter, and forest raw honey.'
),
(
    '77777777-7777-7777-7777-777777777777',
    '9148332211',
    'Ananya Iyer',
    'Bengaluru Millet Bakes & Filter Coffee Blends',
    'anu-bakes',
    'Bengaluru',
    'Malleshwaram',
    'en-IN',
    'ananyaiyer@okaxis',
    'Home Bakery',
    '{"color": "#0284C7", "tagline": "Gluten-free Ragi Brownies & Freshly Roasted Chicory Coffee"}'::jsonb,
    'Guilt-free artisanal bakery crafted with organic Karnataka millets and palm jaggery.'
),
(
    '88888888-8888-8888-8888-888888888888',
    '9342778899',
    'Laxmi Angadi',
    'Laxmi Wood-Pressed Oils & Heritage Pickles',
    'laxmi-organics',
    'Bagalkote',
    'Guledgudd',
    'kn-IN',
    'laxmiangadi@sbi',
    'Organic Produce',
    '{"color": "#15803D", "tagline": "Traditional Ghani Groundnut & Sesame Oils with Sun Pickles"}'::jsonb,
    'Farm-sourced wood-pressed pure oils and grandmother recipe sun pickles.'
);

-- Insert Product Listings for Sellers
insert into public.listings (id, seller_id, title, price, unit, category, description_local, description_en, available)
values
-- Renuka (Hubballi)
('a1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Shenga Holige (Peanut Puran Poli)', 220.00, 'pack of 10', 'Sweets & Snacks', 'ಶುದ್ಧ ತುಪ್ಪ ಮತ್ತು ಬೆಲ್ಲದ ಶೇಂಗಾ ಹೋಳಿಗೆ', 'Traditional crisp peanut stuffed sweet flatbread made with pure jaggery and ghee', true),
('a1111111-1111-1111-1111-111111111112', '11111111-1111-1111-1111-111111111111', 'Bele Holige (Chana Dal Poli)', 250.00, 'pack of 10', 'Sweets & Snacks', 'ಮೃದುವಾದ ಕಡಲೆ ಬೇಳೆ ಹೋಳಿಗೆ', 'Soft chana dal puran poli with cardamom fragrance and pure cow ghee', true),
('a1111111-1111-1111-1111-111111111113', '11111111-1111-1111-1111-111111111111', 'Pure Desi Cow Ghee', 450.00, '500 ml jar', 'Dairy & Ghee', 'ಮನೆಯಲ್ಲೇ ತಯಾರಿಸಿದ ಹಸುವಿನ ತುಪ್ಪ', 'Freshly churned aromatic clarified butter from local grass-fed cows', true),

-- Sunita (Belagavi)
('b2222222-2222-2222-2222-222222222221', '22222222-2222-2222-2222-222222222222', 'Spicy Shenga Chutney Pudi', 140.00, '250g packet', 'Masalas & Podis', 'ಉತ್ತರ ಕರ್ನಾಟಕ ಶೈಲಿಯ ಖಾರದ ಶೇಂಗಾ ಪುಡಿ', 'Spicy roasted peanut garlic chutney powder for idli, dosa and jowar rotti', true),
('b2222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Agasi Chutney Pudi (Flaxseed)', 160.00, '250g packet', 'Masalas & Podis', 'ಆರೋಗ್ಯಕರ ಅಗಸಿ ಬೀಜದ ಚಟ್ನಿ ಪುಡಿ', 'Omega-3 rich roasted flaxseed chutney powder with Byadgi chili', true),

-- Shweta (Mysuru)
('c3333333-3333-3333-3333-333333333331', '33333333-3333-3333-3333-333333333333', 'Handcrafted Mysore Silk Potli Bag', 340.00, 'set of 2', 'Handicrafts & Tailoring', 'ಮೈಸೂರು ರೇಷ್ಮೆಯ ಸುಂದರ ಬ್ಯಾಗ್', 'Handwoven festive zari border gift bag handcrafted by local artisans', true),
('c3333333-3333-3333-3333-333333333332', '33333333-3333-3333-3333-333333333333', 'Natural Sandalwood Herbal Agarbatti', 180.00, 'pack of 30 sticks', 'Handicrafts & Tailoring', 'ನೈಸರ್ಗಿಕ ಗಂಧದ ಅಗರಬತ್ತಿ', 'Aromatic natural Mysore sandalwood incense sticks made from essential oils', true),

-- Kavita (Mangaluru)
('d4444444-4444-4444-4444-444444444441', '44444444-4444-4444-4444-444444444444', 'Mangalore Cashew Macaroons', 260.00, '250g box', 'Sweets & Snacks', 'ಕರಾವಳಿ ಗೋಡಂಬಿ ಮ್ಯಾಕ್ರೂನ್', 'Light, crispy melt-in-mouth egg-free cashew nut treats', true),
('d4444444-4444-4444-4444-444444444442', '44444444-4444-4444-4444-444444444444', 'Halasina Hannu (Jackfruit) Halwa', 240.00, '400g pack', 'Sweets & Snacks', 'ಹಲಸಿನ ಹಣ್ಣಿನ ಸಾಂಪ್ರದಾಯಿಕ ಹಲ್ವಾ', 'Traditional slow-cooked coastal ripe jackfruit sweet preserve in pure ghee', true),

-- Savita (Kalaburagi)
('e5555555-5555-5555-5555-555555555551', '55555555-5555-5555-5555-555555555555', 'Kadak Jowar Rotti Pack', 150.00, 'pack of 10 rottis', 'Tiffin & Meals', 'ಗರಿಗರಿಯಾದ ಜೋಳದ ರೊಟ್ಟಿ', 'Crispy traditional North Karnataka sorghum flatbread with 3-month shelf life', true),
('e5555555-5555-5555-5555-555555555552', '55555555-5555-5555-5555-555555555555', 'Badanekayi Ennegai Gravy', 160.00, '500g container', 'Tiffin & Meals', 'ಮಸಾಲೆ ತುಂಬಿದ ಬದನೆಕಾಯಿ ಪಲ್ಯ', 'Stuffed baby brinjals simmered in rich peanut-sesame masala gravy for rotti', true),

-- Nandini (Shivamogga)
('f6666666-6666-6666-6666-666666666661', '66666666-6666-6666-6666-666666666666', 'Single-Origin Malnad Black Pepper', 290.00, '250g jar', 'Organic Produce', 'ಮಲೆನಾಡಿನ ಶುದ್ಧ ಕಪ್ಪು ಮೆಣಸು', 'Sun-dried aromatic whole black pepper handpicked from Western Ghats estates', true),
('f6666666-6666-6666-6666-666666666662', '66666666-6666-6666-6666-666666666666', 'Raw Forest Blossom Honey', 380.00, '500g glass bottle', 'Organic Produce', 'ಕಾಡಿನ ಶುದ್ಧ ಜೇನುತುಪ್ಪ', 'Unprocessed wild honey harvested sustainably from Thirthahalli forest flora', true),

-- Ananya (Bengaluru)
('g7777777-7777-7777-7777-777777777771', '77777777-7777-7777-7777-777777777777', 'Ragi Dark Chocolate Brownies', 320.00, 'box of 4 squares', 'Home Bakery', 'ರಾಗಿ ಮತ್ತು ಡಾರ್ಕ್ ಚಾಕೊಲೇಟ್ ಬ್ರೌನೀಸ್', 'Fudgy gluten-free finger-millet brownies sweetened with organic palm jaggery', true),
('g7777777-7777-7777-7777-777777777772', '77777777-7777-7777-7777-777777777777', 'Traditional Kumbakonam-Style Filter Coffee Powder', 220.00, '250g pack (80:20)', 'Home Bakery', 'ಮನೆ ಶೈಲಿಯ ಫಿಲ್ಟರ್ ಕಾಫಿ ಪುಡಿ', 'Freshly ground premium Arabica & Robusta beans with roasted chicory blend', true),

-- Laxmi (Bagalkote)
('h8888888-8888-8888-8888-888888888881', '88888888-8888-8888-8888-888888888888', 'Wood-Pressed Groundnut Oil', 290.00, '1 Litre bottle', 'Organic Produce', 'ಶುದ್ಧ ಮರದ ಗಾಣದ ಶೇಂಗಾ ಎಣ್ಣೆ', 'Cold-extracted unrefined peanut oil pressed in traditional wooden Ghani', true),
('h8888888-8888-8888-8888-888888888882', '88888888-8888-8888-8888-888888888888', 'Sun-Cured Raw Mango Pickle', 180.00, '400g glass jar', 'Masalas & Podis', 'ಮನೆ ಮದ್ದಿನ ಮಾವಿನಕಾಯಿ ಉಪ್ಪಿನಕಾಯಿ', 'Sun-fermented raw mango pickle with mustard seeds and cold-pressed sesame oil', true);

-- 9. SEED ORDER HISTORY ACROSS 12 WEEKS
do $$
declare
    seller1 uuid := '11111111-1111-1111-1111-111111111111';
    w int;
    dt timestamp with time zone;
begin
    for w in 0..11 loop
        dt := now() - (w * interval '7 days') - interval '2 days';

        insert into public.orders (seller_id, listing_id, items, buyer_name, buyer_phone, qty, amount, status, fulfilment, created_at)
        values (seller1, 'a1111111-1111-1111-1111-111111111111', '[{"title": "Shenga Holige", "price": 220, "qty": 2}]'::jsonb, 'Praveen Joshi', '9845110001', 2, 440.00, 'delivered', 'rider', dt);

        insert into public.orders (seller_id, listing_id, items, buyer_name, buyer_phone, qty, amount, status, fulfilment, created_at)
        values (seller1, 'a1111111-1111-1111-1111-111111111112', '[{"title": "Bele Holige", "price": 250, "qty": 1}, {"title": "Pure Desi Cow Ghee", "price": 450, "qty": 1}]'::jsonb, 'Suman Hegde', '9845110002', 2, 700.00, 'delivered', 'pickup', dt + interval '1 day');
    end loop;
end;
$$;
