insert into public.organizations (id, name, slug, ruc, address, phone, email, tax_rate, currency)
values (
  '7e80b22f-b06a-4025-937a-5f9d62d78733',
  'SERVICIOS GENERALES UNITED E.I.R.L.',
  'katsumoto',
  '20608183672',
  'Pichanaqui, Junin',
  '999999999',
  'admin@katsumoto.local',
  0.18,
  'PEN'
)
on conflict (id) do update set name = excluded.name, ruc = excluded.ruc;

insert into public.branches (id, organization_id, name, code, type, address, department_code, province_code, district_code, is_selva_zone, invoice_serie_prefix, stock_source_branch_id, is_active, is_default)
values
  ('11111111-1111-4111-8111-111111111111', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Almacen Central', 'ALM', 'warehouse', 'Pichanaqui', '12', '1206', '120606', true, 'F001', null, true, false),
  ('22222222-2222-4222-8222-222222222222', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Sede Pichanaqui', 'PICH', 'pos', 'Pichanaqui', '12', '1206', '120606', true, 'F001', null, true, true),
  ('33333333-3333-4333-8333-333333333333', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Tienda Virtual', 'WEB', 'online', 'Pichanaqui', '12', '1206', '120606', true, 'B001', '11111111-1111-4111-8111-111111111111', true, false)
on conflict (organization_id, code) do update set
  name = excluded.name,
  type = excluded.type,
  stock_source_branch_id = excluded.stock_source_branch_id,
  is_active = true;

insert into public.customers (id, organization_id, name, document_type, document_number, address)
values
  ('44444444-4444-4444-8444-444444444444', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Consumidor Final', 'DNI', '00000000', '-'),
  ('55555555-5555-4555-8555-555555555555', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'TRANSPORTES ANDINOS S.A.C.', 'RUC', '20552123456', 'Av. Los Olivos 456')
on conflict (organization_id, document_type, document_number) do update set name = excluded.name;

insert into public.products (id, organization_id, name, sku, barcode, product_family, category_group, category, description, unit, price_cents, cost_cents, stock, min_stock, max_stock, tax_affectation, tags, is_active)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Aceite 2T Castrol 500ml', 'ACEI-001', '775000000001', 'productos', 'repuestos', 'Cadena', 'Aceite para motor dos tiempos', 'NIU', 2500, 1800, 50, 5, 200, 'gravado', array['aceite','motor'], true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Filtro de aire Stihl FS-250', 'FILT-001', '775000000002', 'productos', 'repuestos', 'Filtro de Aire', 'Filtro de aire compatible', 'NIU', 3500, 2500, 50, 5, 200, 'gravado', array['filtro'], true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Bujia NGK BPMR7A', 'BUJI-001', '775000000003', 'productos', 'repuestos', 'Bujia', 'Bujia para motosierra', 'NIU', 1500, 1000, 50, 5, 200, 'gravado', array['bujia'], true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Cadena 3/8 72 eslabones Oregon', 'CADE-001', '775000000004', 'productos', 'repuestos', 'Cadena', 'Cadena Oregon', 'NIU', 12000, 8500, 50, 2, 100, 'gravado', array['cadena'], true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'Servicio de Mantenimiento', 'SERV-001', '775000000005', 'servicios', 'maintenance', 'Servicio', 'Mano de obra de mantenimiento', 'NIU', 8000, 0, 999, 0, 999, 'gravado', array['servicio'], true)
on conflict (organization_id, sku) do update set name = excluded.name, price_cents = excluded.price_cents, is_active = true;

insert into public.branch_stock (branch_id, product_id, stock, min_stock, max_stock)
select b.id, p.id, case when b.type = 'warehouse' then 100 else 50 end, p.min_stock, p.max_stock
from public.branches b
cross join public.products p
where b.organization_id = '7e80b22f-b06a-4025-937a-5f9d62d78733'
  and b.stock_source_branch_id is null
  and p.organization_id = '7e80b22f-b06a-4025-937a-5f9d62d78733'
on conflict (branch_id, product_id) do update set stock = excluded.stock, min_stock = excluded.min_stock, max_stock = excluded.max_stock;

insert into public.managed_category_families (id, organization_id, key, label, icon, color, active_color, sort_order)
values
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'productos', 'Productos', 'Package', 'text-orange-700', 'bg-orange-600 text-white', 1),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'servicios', 'Servicios', 'Wrench', 'text-blue-700', 'bg-blue-600 text-white', 2)
on conflict (organization_id, key) do update set label = excluded.label;

insert into public.managed_category_groups (id, organization_id, family_id, key, label, icon, color, sort_order)
values
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc1', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'repuestos', 'Repuestos', 'Cog', 'text-orange-700', 1),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc2', '7e80b22f-b06a-4025-937a-5f9d62d78733', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', 'maintenance', 'Mantenimiento', 'Wrench', 'text-blue-700', 1)
on conflict (organization_id, key) do update set label = excluded.label;

insert into public.managed_categories (organization_id, group_id, name, sort_order)
values
  ('7e80b22f-b06a-4025-937a-5f9d62d78733', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'Cadena', 1),
  ('7e80b22f-b06a-4025-937a-5f9d62d78733', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'Filtro de Aire', 2),
  ('7e80b22f-b06a-4025-937a-5f9d62d78733', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'Bujia', 3),
  ('7e80b22f-b06a-4025-937a-5f9d62d78733', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2', 'Servicio', 1);

insert into public.cash_registers (organization_id, branch_id, number, status, opening_amount_cents)
values ('7e80b22f-b06a-4025-937a-5f9d62d78733', '22222222-2222-4222-8222-222222222222', 1, 'open', 50000)
on conflict do nothing;

insert into public.sunat_config (organization_id, ruc, razon_social, nombre_comercial, ubigeo, departamento, provincia, distrito, direccion, usuario_sol, modo_produccion, is_configured, ticket_footer)
values ('7e80b22f-b06a-4025-937a-5f9d62d78733', '20608183672', 'SERVICIOS GENERALES UNITED E.I.R.L.', 'Katsumoto', '120606', 'JUNIN', 'CHANCHAMAYO', 'PICHANAQUI', 'Pichanaqui, Junin', 'MODDATOS', false, false, 'Gracias por su compra')
on conflict (organization_id) do update set razon_social = excluded.razon_social;

insert into public.tax_configurations (organization_id, seller_department_code, seller_province_code, seller_district_code, seller_is_selva, selva_law_enabled, default_tax_affectation)
values ('7e80b22f-b06a-4025-937a-5f9d62d78733', '12', '1206', '120606', true, true, 'gravado');
