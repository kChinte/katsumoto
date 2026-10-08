create extension if not exists pgcrypto;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  ruc text not null,
  address text,
  phone text,
  email text,
  tax_rate numeric not null default 0.18,
  currency text not null default 'PEN',
  logo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key,
  email text not null,
  full_name text,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  role text not null default 'reader',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_role_check check (role in ('owner', 'admin', 'user'))
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  type text not null default 'pos',
  address text,
  phone text,
  department_code text not null default '',
  province_code text not null default '',
  district_code text not null default '',
  is_selva_zone boolean not null default false,
  invoice_serie_prefix text not null default 'F001',
  is_active boolean not null default true,
  is_default boolean not null default false,
  stock_source_branch_id uuid references public.branches(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  document_type text not null,
  document_number text not null,
  phone text,
  email text,
  address text,
  city text,
  department_code text not null default '',
  province_code text not null default '',
  district_code text not null default '',
  is_selva_zone boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, document_type, document_number)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  sku text not null,
  barcode text not null default '',
  product_family text not null default 'productos',
  category_group text not null default 'repuestos',
  category text not null default '',
  description text,
  unit text not null default 'NIU',
  price_cents bigint not null default 0,
  cost_cents bigint not null default 0,
  stock integer not null default 0,
  min_stock integer not null default 0,
  max_stock integer not null default 0,
  supplier text,
  image_url text,
  tax_affectation text not null default 'gravado',
  tags text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table public.branch_stock (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  stock integer not null default 0,
  min_stock integer not null default 0,
  max_stock integer not null default 0,
  unique (branch_id, product_id)
);

create table public.price_tiers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  min_quantity integer not null,
  price_cents bigint not null default 0,
  label text not null default '',
  unique (product_id, min_quantity)
);

create table public.machine_models (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  brand text not null default '',
  model text not null default '',
  category text not null default 'otro',
  year integer,
  description text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.product_machines (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  machine_model_id uuid not null references public.machine_models(id) on delete cascade,
  unique (product_id, machine_model_id)
);

create table public.managed_category_families (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  key text not null,
  label text not null,
  icon text not null default 'Package',
  color text not null default '',
  active_color text not null default '',
  sort_order integer not null default 0,
  unique (organization_id, key)
);

create table public.managed_category_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  family_id uuid references public.managed_category_families(id) on delete cascade,
  key text not null,
  label text not null,
  icon text not null default 'Tag',
  color text not null default '',
  sort_order integer not null default 0,
  unique (organization_id, key)
);

create table public.managed_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  group_id uuid references public.managed_category_groups(id) on delete cascade,
  name text not null,
  image_url text,
  sort_order integer not null default 0
);

create table public.cash_registers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  number integer not null default 1,
  status text not null default 'open',
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opened_by uuid,
  closed_by uuid,
  opening_amount_cents bigint not null default 0,
  closing_amount_cents bigint,
  expected_closing_cents bigint,
  difference_cents bigint
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  number text not null,
  serie text not null,
  correlativo integer not null,
  invoice_type text not null,
  customer_id uuid references public.customers(id),
  branch_id uuid references public.branches(id),
  status text not null default 'draft',
  issue_date date not null default current_date,
  due_date date,
  subtotal_cents bigint not null default 0,
  gravada_cents bigint not null default 0,
  exonerada_cents bigint not null default 0,
  inafecta_cents bigint not null default 0,
  exportacion_cents bigint not null default 0,
  igv_rate numeric not null default 0.18,
  igv_cents bigint not null default 0,
  total_cents bigint not null default 0,
  payment_method text,
  register_id uuid references public.cash_registers(id),
  notes text,
  created_by uuid,
  reference_invoice_id uuid references public.invoices(id),
  motivo_nota text,
  descripcion_motivo text,
  sunat_hash text,
  sunat_xml_path text,
  sunat_cdr_path text,
  sunat_ticket text,
  sunat_error_code text,
  sunat_error_message text,
  sunat_sent_at timestamptz,
  sunat_accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, serie, correlativo)
);

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  product_sku text,
  quantity integer not null default 1,
  unit_price_cents bigint not null default 0,
  discount_percent numeric not null default 0,
  discount_cents bigint not null default 0,
  line_total_cents bigint not null default 0,
  tax_affectation text not null default 'gravado',
  igv_cents bigint not null default 0,
  created_at timestamptz not null default now()
);

create table public.register_transactions (
  id uuid primary key default gen_random_uuid(),
  register_id uuid not null references public.cash_registers(id) on delete cascade,
  invoice_id uuid references public.invoices(id),
  payment_method text not null default 'cash',
  amount_cents bigint not null default 0,
  description text not null default '',
  created_at timestamptz not null default now()
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id),
  branch_id uuid not null references public.branches(id),
  movement_type text not null,
  quantity integer not null,
  reference_type text,
  reference_id uuid,
  transfer_to_branch_id uuid references public.branches(id),
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint stock_movements_movement_type_check check (movement_type in ('in', 'out', 'adjustment', 'transfer', 'transfer_out', 'transfer_in', 'return'))
);

create table public.store_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  order_number text not null,
  customer_name text not null,
  customer_phone text not null default '',
  customer_email text not null default '',
  customer_document_type text not null default 'DNI',
  customer_document_number text not null default '',
  branch_id uuid references public.branches(id),
  shipping_address text,
  shipping_department_code text not null default '',
  shipping_province_code text not null default '',
  shipping_district_code text not null default '',
  subtotal_cents bigint not null default 0,
  gravada_cents bigint not null default 0,
  exonerada_cents bigint not null default 0,
  inafecta_cents bigint not null default 0,
  igv_cents bigint not null default 0,
  total_cents bigint not null default 0,
  status text not null default 'pending',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, order_number)
);

create table public.store_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.store_orders(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  product_sku text,
  quantity integer not null default 1,
  unit_price_cents bigint not null default 0,
  line_total_cents bigint not null default 0,
  tax_affectation text not null default 'gravado',
  igv_cents bigint not null default 0
);

create table public.despatches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id),
  serie text not null,
  correlativo integer not null,
  status text not null default 'draft',
  issue_date date not null default current_date,
  motivo_traslado text not null default '01',
  descripcion_motivo text not null default '',
  fecha_inicio_traslado date not null default current_date,
  peso_bruto_total numeric not null default 0,
  numero_bultos integer not null default 1,
  remitente_ubigeo text not null default '',
  remitente_direccion text not null default '',
  destino_ubigeo text not null default '',
  destino_direccion text not null default '',
  destinatario_tipo_doc text not null default '6',
  destinatario_documento text not null default '',
  destinatario_nombre text not null default '',
  transportista_tipo_doc text not null default '6',
  transportista_documento text not null default '',
  transportista_nombre text not null default '',
  conductor_tipo_doc text not null default '1',
  conductor_documento text not null default '',
  conductor_nombre text not null default '',
  conductor_licencia text not null default '',
  vehiculo_placa text not null default '',
  sunat_hash text,
  sunat_xml_path text,
  sunat_cdr_path text,
  sunat_ticket text,
  sunat_error_code text,
  sunat_error_message text,
  sunat_sent_at timestamptz,
  sunat_accepted_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, serie, correlativo),
  constraint despatches_status_check check (status in ('draft', 'issued', 'accepted', 'cancelled'))
);

create table public.despatch_items (
  id uuid primary key default gen_random_uuid(),
  despatch_id uuid not null references public.despatches(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  product_sku text,
  quantity integer not null default 1,
  unit text not null default 'NIU',
  created_at timestamptz not null default now()
);

create table public.sunat_config (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade unique,
  ruc text not null default '',
  razon_social text not null default '',
  nombre_comercial text not null default '',
  ubigeo text not null default '',
  departamento text not null default '',
  provincia text not null default '',
  distrito text not null default '',
  direccion text not null default '',
  usuario_sol text not null default '',
  clave_sol_encrypted text,
  certificado_path text,
  certificado_password_encrypted text,
  gre_client_id text,
  gre_client_secret text,
  modo_produccion boolean not null default false,
  is_configured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sunat_summary_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tipo text not null,
  ticket text,
  fecha_referencia date not null default current_date,
  status text not null default 'pending',
  cdr_path text,
  error_code text,
  error_message text,
  xml_path text,
  created_at timestamptz not null default now()
);

create table public.tax_configurations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  seller_department_code text not null default '',
  seller_province_code text not null default '',
  seller_district_code text not null default '',
  seller_is_selva boolean not null default false,
  selva_law_enabled boolean not null default false,
  default_tax_affectation text not null default 'gravado',
  legal_text_template text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  user_id uuid,
  action text not null,
  entity text not null,
  entity_id uuid,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.get_next_correlativo(p_organization_id uuid, p_serie text)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_next integer;
begin
  select coalesce(max(correlativo), 0) + 1
  into v_next
  from public.invoices
  where organization_id = p_organization_id and serie = p_serie;
  return v_next;
end;
$$;

create or replace function public.insert_audit_entry(
  p_action text,
  p_entity text,
  p_entity_id uuid default null,
  p_old_value jsonb default null,
  p_new_value jsonb default null,
  p_organization_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
  v_org uuid := p_organization_id;
begin
  if v_org is null and v_user is not null then
    select organization_id into v_org from public.profiles where id = v_user limit 1;
  end if;

  insert into public.audit_log (organization_id, user_id, action, entity, entity_id, old_value, new_value)
  values (v_org, v_user, p_action, p_entity, p_entity_id, p_old_value, p_new_value)
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.fulfill_store_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
begin
  update public.store_orders
  set status = 'completed', updated_at = now()
  where id = p_order_id;
  return p_order_id;
end;
$$;

grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables in schema public to anon, authenticated, service_role;
grant all privileges on all routines in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
