-- ============================================================
-- Unificacion Tienda Virtual + Almacen Central
--
-- Modelo:
--   - branches.branch_id / invoices.branch_id = sede/canal comercial
--   - invoices.stock_branch_id = sede fisica que descuenta stock
--   - branches.stock_source_branch_id permite que Tienda Virtual use
--     el stock del Almacen Central sin duplicar inventario.
-- ============================================================

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS stock_branch_id uuid REFERENCES public.branches(id),
  ADD COLUMN IF NOT EXISTS sales_channel text NOT NULL DEFAULT 'admin_manual',
  ADD COLUMN IF NOT EXISTS source_order_id uuid REFERENCES public.store_orders(id);

ALTER TABLE public.store_orders
  ADD COLUMN IF NOT EXISTS source_channel text NOT NULL DEFAULT 'web_public',
  ADD COLUMN IF NOT EXISTS stock_branch_id uuid REFERENCES public.branches(id);

ALTER TABLE public.stock_movements
  ADD COLUMN IF NOT EXISTS sale_branch_id uuid REFERENCES public.branches(id),
  ADD COLUMN IF NOT EXISTS source_channel text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'invoices_sales_channel_check'
  ) THEN
    ALTER TABLE public.invoices
      ADD CONSTRAINT invoices_sales_channel_check
      CHECK (sales_channel IN ('pos', 'admin_online_pos', 'web_public', 'admin_manual'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'store_orders_source_channel_check'
  ) THEN
    ALTER TABLE public.store_orders
      ADD CONSTRAINT store_orders_source_channel_check
      CHECK (source_channel IN ('web_public', 'admin_online'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'branches_stock_source_not_self_check'
  ) THEN
    ALTER TABLE public.branches
      ADD CONSTRAINT branches_stock_source_not_self_check
      CHECK (stock_source_branch_id IS NULL OR stock_source_branch_id <> id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.resolve_stock_branch(p_branch_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT COALESCE(b.stock_source_branch_id, b.id)
  FROM public.branches b
  WHERE b.id = p_branch_id
$$;

WITH warehouse_per_org AS (
  SELECT
    organization_id,
    (array_agg(id ORDER BY created_at, id))[1] AS warehouse_id,
    COUNT(*) AS warehouse_count
  FROM public.branches
  WHERE type = 'warehouse' AND is_active = true
  GROUP BY organization_id
)
UPDATE public.branches b
SET stock_source_branch_id = w.warehouse_id
FROM warehouse_per_org w
WHERE b.organization_id = w.organization_id
  AND b.type = 'online'
  AND b.stock_source_branch_id IS NULL
  AND w.warehouse_count = 1;

UPDATE public.invoices
SET
  stock_branch_id = COALESCE(stock_branch_id, public.resolve_stock_branch(branch_id)),
  sales_channel = CASE
    WHEN sales_channel IS NOT NULL AND sales_channel <> 'admin_manual' THEN sales_channel
    WHEN payment_method = 'online' OR notes ILIKE 'Pedido web %' THEN 'web_public'
    ELSE 'admin_manual'
  END
WHERE stock_branch_id IS NULL
   OR sales_channel = 'admin_manual';

UPDATE public.store_orders
SET
  source_channel = COALESCE(source_channel, 'web_public'),
  stock_branch_id = COALESCE(stock_branch_id, public.resolve_stock_branch(branch_id))
WHERE stock_branch_id IS NULL;

UPDATE public.stock_movements sm
SET
  sale_branch_id = COALESCE(sm.sale_branch_id, i.branch_id, sm.branch_id),
  source_channel = COALESCE(sm.source_channel, i.sales_channel, 'admin_manual')
FROM public.invoices i
WHERE sm.reference_type IN ('invoice', 'credit_note')
  AND sm.reference_id = i.id;

UPDATE public.stock_movements
SET
  sale_branch_id = COALESCE(sale_branch_id, branch_id),
  source_channel = COALESCE(source_channel, 'admin_manual')
WHERE sale_branch_id IS NULL OR source_channel IS NULL;

DROP FUNCTION IF EXISTS public.create_invoice_with_items(
    uuid, text, integer, text, text, uuid,
    bigint, bigint, bigint, bigint, bigint, numeric,
    bigint, bigint, text, uuid, text, uuid, uuid, jsonb
);

DROP FUNCTION IF EXISTS public.create_invoice_with_items(
    uuid, text, integer, text, text, uuid,
    bigint, bigint, bigint, bigint, bigint, numeric,
    bigint, bigint, text, uuid, text, uuid, uuid, jsonb, text, uuid
);

CREATE OR REPLACE FUNCTION public.create_invoice_with_items(
    p_organization_id uuid,
    p_serie text,
    p_correlativo integer,
    p_invoice_type text,
    p_customer_id text,
    p_branch_id uuid,
    p_subtotal_cents bigint,
    p_gravada_cents bigint,
    p_exonerada_cents bigint,
    p_inafecta_cents bigint,
    p_exportacion_cents bigint,
    p_igv_rate numeric,
    p_igv_cents bigint,
    p_total_cents bigint,
    p_payment_method text,
    p_register_id uuid,
    p_notes text,
    p_created_by uuid,
    p_reference_invoice_id uuid,
    p_items jsonb,
    p_sales_channel text DEFAULT 'admin_manual',
    p_source_order_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_invoice_id UUID;
    v_number TEXT;
    v_item JSONB;
    v_product_org_id UUID;
    v_stock_branch_id UUID;
    v_calc_subtotal BIGINT := 0;
    v_calc_igv BIGINT := 0;
    v_calc_gravada BIGINT := 0;
    v_calc_exonerada BIGINT := 0;
    v_calc_inafecta BIGINT := 0;
    v_calc_exportacion BIGINT := 0;
    v_aff TEXT;
    v_line BIGINT;
    v_igv BIGINT;
BEGIN
    IF p_created_by IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_created_by AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Usuario no pertenece a la organizacion';
    END IF;

    SELECT public.resolve_stock_branch(p_branch_id) INTO v_stock_branch_id;

    IF v_stock_branch_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.branches
        WHERE id = p_branch_id AND organization_id = p_organization_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Sede no pertenece a la organizacion';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.branches
        WHERE id = v_stock_branch_id AND organization_id = p_organization_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Sede de stock no pertenece a la organizacion';
    END IF;

    IF p_sales_channel NOT IN ('pos', 'admin_online_pos', 'web_public', 'admin_manual') THEN
        RAISE EXCEPTION 'Canal de venta invalido: %', p_sales_channel;
    END IF;

    IF p_reference_invoice_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.invoices
        WHERE id = p_reference_invoice_id AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Comprobante referenciado no pertenece a la organizacion';
    END IF;

    IF p_source_order_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.store_orders
        WHERE id = p_source_order_id AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Pedido origen no pertenece a la organizacion';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_line := (v_item->>'line_total_cents')::BIGINT;
        v_igv := COALESCE((v_item->>'igv_cents')::BIGINT, 0);
        v_aff := COALESCE(v_item->>'tax_affectation', 'gravado');
        v_calc_subtotal := v_calc_subtotal + v_line;
        v_calc_igv := v_calc_igv + v_igv;
        IF v_aff = 'gravado' THEN
            v_calc_gravada := v_calc_gravada + (v_line - v_igv);
        ELSIF v_aff = 'exonerado' THEN
            v_calc_exonerada := v_calc_exonerada + v_line;
        ELSIF v_aff = 'exportacion' THEN
            v_calc_exportacion := v_calc_exportacion + v_line;
        ELSE
            v_calc_inafecta := v_calc_inafecta + v_line;
        END IF;
    END LOOP;

    IF v_calc_subtotal <> p_subtotal_cents
       OR v_calc_igv <> p_igv_cents
       OR v_calc_gravada <> p_gravada_cents
       OR v_calc_exonerada <> p_exonerada_cents
       OR v_calc_inafecta <> p_inafecta_cents
       OR v_calc_exportacion <> p_exportacion_cents
       OR p_total_cents <> p_subtotal_cents
    THEN
        RAISE EXCEPTION 'Montos del comprobante inconsistentes con los items';
    END IF;

    v_number := p_serie || '-' || LPAD(p_correlativo::text, 6, '0');

    INSERT INTO public.invoices (
        organization_id, number, serie, correlativo, invoice_type,
        customer_id, branch_id, stock_branch_id, sales_channel, source_order_id, status,
        subtotal_cents, gravada_cents, exonerada_cents, inafecta_cents,
        exportacion_cents, igv_rate, igv_cents, total_cents,
        payment_method, register_id, notes, created_by, reference_invoice_id
    ) VALUES (
        p_organization_id, v_number, p_serie, p_correlativo, p_invoice_type,
        p_customer_id::uuid, p_branch_id, v_stock_branch_id, p_sales_channel, p_source_order_id, 'issued',
        p_subtotal_cents, p_gravada_cents, p_exonerada_cents, p_inafecta_cents,
        p_exportacion_cents, p_igv_rate, p_igv_cents, p_total_cents,
        p_payment_method, p_register_id, p_notes, p_created_by, p_reference_invoice_id
    ) RETURNING id INTO v_invoice_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO public.invoice_items (
            invoice_id, product_id, product_name, product_sku,
            quantity, unit_price_cents, discount_percent,
            discount_cents, line_total_cents, tax_affectation, igv_cents
        ) VALUES (
            v_invoice_id,
            (v_item->>'product_id')::UUID,
            v_item->>'product_name',
            v_item->>'product_sku',
            (v_item->>'quantity')::INTEGER,
            (v_item->>'unit_price_cents')::BIGINT,
            COALESCE((v_item->>'discount_percent')::NUMERIC, 0),
            COALESCE((v_item->>'discount_cents')::BIGINT, 0),
            (v_item->>'line_total_cents')::BIGINT,
            COALESCE(v_item->>'tax_affectation', 'gravado'),
            COALESCE((v_item->>'igv_cents')::BIGINT, 0)
        );

        IF (v_item->>'product_id') IS NOT NULL THEN
            SELECT organization_id INTO v_product_org_id
            FROM public.products
            WHERE id = (v_item->>'product_id')::UUID;

            IF v_product_org_id IS NULL THEN
                RAISE EXCEPTION 'Producto no encontrado: %', (v_item->>'product_name');
            END IF;

            IF v_product_org_id != p_organization_id THEN
                RAISE EXCEPTION 'Producto no pertenece a la organizacion: %', (v_item->>'product_name');
            END IF;

            UPDATE public.branch_stock
            SET stock = stock - (v_item->>'quantity')::INTEGER
            WHERE branch_id = v_stock_branch_id
              AND product_id = (v_item->>'product_id')::UUID
              AND stock >= (v_item->>'quantity')::INTEGER;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Stock insuficiente para: %', (v_item->>'product_name');
            END IF;

            INSERT INTO public.stock_movements (
                organization_id, product_id, branch_id, sale_branch_id, movement_type,
                quantity, reference_type, reference_id, source_channel, created_by
            ) VALUES (
                p_organization_id,
                (v_item->>'product_id')::UUID,
                v_stock_branch_id,
                p_branch_id,
                'out',
                (v_item->>'quantity')::INTEGER,
                'invoice',
                v_invoice_id,
                p_sales_channel,
                p_created_by
            );
        END IF;
    END LOOP;

    RETURN v_invoice_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_credit_note(
    p_organization_id uuid,
    p_parent_invoice_id uuid,
    p_items jsonb,
    p_motivo_nota text,
    p_descripcion_motivo text,
    p_branch_id uuid,
    p_created_by uuid,
    p_notes text DEFAULT NULL::text
)
RETURNS TABLE(invoice_id uuid, serie text, correlativo integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_invoice_id UUID;
    v_parent RECORD;
    v_stock_branch_id UUID;
    v_serie TEXT;
    v_correlativo INTEGER;
    v_number TEXT;
    v_item JSONB;
    v_subtotal_cents BIGINT := 0;
    v_gravada_cents BIGINT := 0;
    v_exonerada_cents BIGINT := 0;
    v_inafecta_cents BIGINT := 0;
    v_exportacion_cents BIGINT := 0;
    v_igv_cents BIGINT := 0;
    v_total_cents BIGINT := 0;
    v_item_line_total BIGINT;
    v_item_igv BIGINT;
    v_item_tax_aff TEXT;
BEGIN
    IF p_created_by IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_created_by AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Usuario no pertenece a la organizacion';
    END IF;

    SELECT * INTO v_parent
    FROM invoices
    WHERE id = p_parent_invoice_id
      AND organization_id = p_organization_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Factura referenciada no encontrada';
    END IF;

    IF v_parent.status NOT IN ('accepted', 'paid') THEN
        RAISE EXCEPTION 'La factura debe estar aceptada o pagada para emitir una NC (estado actual: %)', v_parent.status;
    END IF;

    IF v_parent.invoice_type NOT IN ('factura', 'boleta') THEN
        RAISE EXCEPTION 'Solo se puede emitir NC de facturas o boletas (tipo actual: %)', v_parent.invoice_type;
    END IF;

    v_stock_branch_id := COALESCE(v_parent.stock_branch_id, public.resolve_stock_branch(p_branch_id), p_branch_id);

    IF v_parent.invoice_type = 'factura' THEN
        v_serie := 'FC01';
    ELSE
        v_serie := 'BC01';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_item_line_total := COALESCE((v_item->>'line_total_cents')::BIGINT, 0);
        v_item_igv := COALESCE((v_item->>'igv_cents')::BIGINT, 0);
        v_item_tax_aff := COALESCE(v_item->>'tax_affectation', 'gravado');

        v_subtotal_cents := v_subtotal_cents + v_item_line_total;
        v_igv_cents := v_igv_cents + v_item_igv;

        IF v_item_tax_aff = 'gravado' THEN
            v_gravada_cents := v_gravada_cents + (v_item_line_total - v_item_igv);
        ELSIF v_item_tax_aff = 'exonerado' THEN
            v_exonerada_cents := v_exonerada_cents + v_item_line_total;
        ELSIF v_item_tax_aff = 'inafecto' THEN
            v_inafecta_cents := v_inafecta_cents + v_item_line_total;
        ELSIF v_item_tax_aff = 'exportacion' THEN
            v_exportacion_cents := v_exportacion_cents + v_item_line_total;
        END IF;
    END LOOP;

    v_total_cents := v_subtotal_cents;

    v_correlativo := get_next_correlativo(p_organization_id, v_serie);
    v_number := v_serie || '-' || LPAD(v_correlativo::TEXT, 6, '0');

    INSERT INTO invoices (
        organization_id, number, serie, correlativo, invoice_type,
        customer_id, branch_id, stock_branch_id, sales_channel, source_order_id, status,
        subtotal_cents, gravada_cents, exonerada_cents, inafecta_cents,
        exportacion_cents, igv_rate, igv_cents, total_cents,
        notes, created_by,
        reference_invoice_id, motivo_nota, descripcion_motivo
    ) VALUES (
        p_organization_id, v_number, v_serie, v_correlativo, 'nota_credito',
        v_parent.customer_id, p_branch_id, v_stock_branch_id, COALESCE(v_parent.sales_channel, 'admin_manual'), v_parent.source_order_id, 'issued',
        v_subtotal_cents, v_gravada_cents, v_exonerada_cents, v_inafecta_cents,
        v_exportacion_cents, v_parent.igv_rate, v_igv_cents, v_total_cents,
        p_notes, p_created_by,
        p_parent_invoice_id, p_motivo_nota, p_descripcion_motivo
    ) RETURNING id INTO v_invoice_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO invoice_items (
            invoice_id, product_id, product_name, product_sku,
            quantity, unit_price_cents, discount_percent,
            discount_cents, line_total_cents, tax_affectation, igv_cents
        ) VALUES (
            v_invoice_id,
            COALESCE((v_item->>'product_id')::UUID, NULL),
            v_item->>'product_name',
            v_item->>'product_sku',
            (v_item->>'quantity')::INTEGER,
            (v_item->>'unit_price_cents')::BIGINT,
            COALESCE((v_item->>'discount_percent')::NUMERIC, 0),
            COALESCE((v_item->>'discount_cents')::BIGINT, 0),
            (v_item->>'line_total_cents')::BIGINT,
            COALESCE(v_item->>'tax_affectation', 'gravado'),
            COALESCE((v_item->>'igv_cents')::BIGINT, 0)
        );

        IF (v_item->>'product_id') IS NOT NULL THEN
            INSERT INTO branch_stock (branch_id, product_id, stock, min_stock)
            VALUES (v_stock_branch_id, (v_item->>'product_id')::UUID, (v_item->>'quantity')::INTEGER, 0)
            ON CONFLICT (branch_id, product_id)
            DO UPDATE SET stock = branch_stock.stock + (v_item->>'quantity')::INTEGER;

            INSERT INTO stock_movements (
                organization_id, product_id, branch_id, sale_branch_id, movement_type,
                quantity, reference_type, reference_id, source_channel, notes, created_by
            ) VALUES (
                p_organization_id,
                (v_item->>'product_id')::UUID,
                v_stock_branch_id,
                p_branch_id,
                'return',
                (v_item->>'quantity')::INTEGER,
                'credit_note',
                v_invoice_id,
                COALESCE(v_parent.sales_channel, 'admin_manual'),
                'NC ' || v_number || ' - ' || p_descripcion_motivo,
                p_created_by
            );
        END IF;
    END LOOP;

    INSERT INTO audit_log (organization_id, user_id, action, entity, entity_id, new_value)
    VALUES (
        p_organization_id, p_created_by, 'credit_note.create', 'invoice', v_invoice_id::TEXT,
        jsonb_build_object(
            'serie', v_serie,
            'correlativo', v_correlativo,
            'parent_invoice', v_parent.number,
            'motivo', p_motivo_nota,
            'total_cents', v_total_cents
        )
    );

    RETURN QUERY SELECT v_invoice_id, v_serie, v_correlativo;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_store_order(
    p_order_number text,
    p_customer_name text,
    p_customer_phone text,
    p_customer_email text,
    p_customer_document_type text,
    p_customer_document_number text,
    p_branch_id uuid,
    p_shipping_address text,
    p_shipping_department_code text,
    p_shipping_province_code text,
    p_shipping_district_code text,
    p_notes text,
    p_items jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_org_id uuid;
    v_stock_branch_id uuid;
    v_branch_selva boolean;
    v_selva_law boolean := false;
    v_item jsonb;
    v_unit_price bigint;
    v_tier_price bigint;
    v_available integer;
    v_qty integer;
    v_line_total bigint;
    v_igv bigint;
    v_aff text;
    v_effective_aff text;
    v_subtotal bigint := 0;
    v_gravada bigint := 0;
    v_exonerada bigint := 0;
    v_inafecta bigint := 0;
    v_igv_total bigint := 0;
    v_order_id uuid;
BEGIN
    SELECT organization_id, is_selva_zone, public.resolve_stock_branch(id)
    INTO v_org_id, v_branch_selva, v_stock_branch_id
    FROM public.branches
    WHERE id = p_branch_id AND is_active = true AND type = 'online';

    IF v_org_id IS NULL OR v_stock_branch_id IS NULL THEN
        RAISE EXCEPTION 'Sucursal online no encontrada';
    END IF;

    SELECT selva_law_enabled INTO v_selva_law
    FROM public.tax_configurations
    WHERE organization_id = v_org_id;

    INSERT INTO public.store_orders (
        organization_id, order_number, customer_name, customer_phone, customer_email,
        customer_document_type, customer_document_number, branch_id, stock_branch_id, source_channel,
        shipping_address, shipping_department_code, shipping_province_code, shipping_district_code,
        status, notes
    ) VALUES (
        v_org_id, p_order_number, p_customer_name, p_customer_phone, p_customer_email,
        p_customer_document_type, p_customer_document_number, p_branch_id, v_stock_branch_id, 'web_public',
        p_shipping_address, p_shipping_department_code, p_shipping_province_code, p_shipping_district_code,
        'pending', p_notes
    ) RETURNING id INTO v_order_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_qty := (v_item->>'quantity')::integer;
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Cantidad invalida para %', v_item->>'product_name';
        END IF;

        SELECT price_cents, tax_affectation INTO v_unit_price, v_aff
        FROM public.products
        WHERE id = (v_item->>'product_id')::uuid
          AND is_active = true
          AND organization_id = v_org_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto no disponible: %', v_item->>'product_name';
        END IF;

        v_available := 0;

        SELECT COALESCE(stock, 0) INTO v_available
        FROM public.branch_stock
        WHERE branch_id = v_stock_branch_id
          AND product_id = (v_item->>'product_id')::uuid;

        IF COALESCE(v_available, 0) < v_qty THEN
            RAISE EXCEPTION 'Stock insuficiente para: %', v_item->>'product_name';
        END IF;

        IF v_unit_price IS NULL THEN
            RAISE EXCEPTION 'El producto % no tiene precio configurado', v_item->>'product_name';
        END IF;

        SELECT price_cents INTO v_tier_price
        FROM public.price_tiers
        WHERE product_id = (v_item->>'product_id')::uuid
          AND min_quantity <= v_qty
        ORDER BY min_quantity DESC
        LIMIT 1;

        IF FOUND THEN
            v_unit_price := v_tier_price;
        END IF;

        v_line_total := v_qty * v_unit_price;

        v_effective_aff := v_aff;
        IF v_effective_aff = 'gravado' AND v_selva_law AND v_branch_selva
           AND (v_item->>'tax_affectation') = 'exonerado' THEN
            v_effective_aff := 'exonerado';
        END IF;

        IF v_effective_aff = 'gravado' THEN
            v_igv := round(v_line_total * 0.18 / 1.18);
            v_gravada := v_gravada + (v_line_total - v_igv);
            v_igv_total := v_igv_total + v_igv;
        ELSIF v_effective_aff = 'exonerado' THEN
            v_igv := 0;
            v_exonerada := v_exonerada + v_line_total;
        ELSE
            v_igv := 0;
            v_inafecta := v_inafecta + v_line_total;
        END IF;

        v_subtotal := v_subtotal + v_line_total;

        INSERT INTO public.store_order_items (
            order_id, product_id, product_name, product_sku,
            quantity, unit_price_cents, line_total_cents, tax_affectation, igv_cents
        ) VALUES (
            v_order_id,
            (v_item->>'product_id')::uuid,
            v_item->>'product_name',
            v_item->>'product_sku',
            v_qty, v_unit_price, v_line_total, v_effective_aff, v_igv
        );
    END LOOP;

    IF v_subtotal = 0 THEN
        RAISE EXCEPTION 'El pedido no tiene items validos';
    END IF;

    UPDATE public.store_orders SET
        subtotal_cents = v_subtotal,
        gravada_cents = v_gravada,
        exonerada_cents = v_exonerada,
        inafecta_cents = v_inafecta,
        igv_cents = v_igv_total,
        total_cents = v_subtotal
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fulfill_store_order(p_order_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_order RECORD;
    v_org_id UUID;
    v_user_id UUID;
    v_stock_branch_id UUID;
    v_customer_id UUID;
    v_invoice_type TEXT;
    v_serie TEXT;
    v_default_serie TEXT;
    v_correlativo INTEGER;
    v_invoice_id UUID;
    v_existing_customer_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    SELECT * INTO v_order
    FROM public.store_orders
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido no encontrado';
    END IF;

    IF v_order.status != 'processing' THEN
        RAISE EXCEPTION 'El pedido debe estar en procesamiento';
    END IF;

    SELECT organization_id INTO v_org_id FROM public.profiles WHERE id = v_user_id;
    IF v_org_id IS NULL OR v_org_id != v_order.organization_id THEN
        RAISE EXCEPTION 'Sin permiso para este pedido';
    END IF;

    v_stock_branch_id := COALESCE(v_order.stock_branch_id, public.resolve_stock_branch(v_order.branch_id));
    IF v_stock_branch_id IS NULL THEN
        RAISE EXCEPTION 'No se encontro la sede fisica de stock para el pedido';
    END IF;

    SELECT id INTO v_existing_customer_id
    FROM public.customers
    WHERE organization_id = v_org_id
      AND document_number = v_order.customer_document_number
    LIMIT 1;

    IF v_existing_customer_id IS NOT NULL THEN
        v_customer_id := v_existing_customer_id;
    ELSE
        INSERT INTO public.customers (organization_id, name, document_type, document_number, phone, email)
        VALUES (v_org_id, v_order.customer_name, v_order.customer_document_type,
                v_order.customer_document_number, v_order.customer_phone, v_order.customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    v_invoice_type := CASE WHEN v_order.customer_document_type = 'RUC' THEN 'factura' ELSE 'boleta' END;
    v_default_serie := CASE WHEN v_invoice_type = 'factura' THEN 'F001' ELSE 'B001' END;

    SELECT COALESCE(invoice_serie_prefix, v_default_serie) INTO v_serie
    FROM public.branches WHERE id = v_order.branch_id;

    v_correlativo := public.get_next_correlativo(v_org_id, v_serie);

    v_invoice_id := public.create_invoice_with_items(
        p_organization_id := v_org_id,
        p_serie := v_serie,
        p_correlativo := v_correlativo,
        p_invoice_type := v_invoice_type,
        p_customer_id := v_customer_id::text,
        p_branch_id := v_order.branch_id,
        p_subtotal_cents := v_order.subtotal_cents,
        p_gravada_cents := v_order.gravada_cents,
        p_exonerada_cents := v_order.exonerada_cents,
        p_inafecta_cents := v_order.inafecta_cents,
        p_exportacion_cents := 0,
        p_igv_rate := 0.18,
        p_igv_cents := v_order.igv_cents,
        p_total_cents := v_order.total_cents,
        p_payment_method := NULL,
        p_register_id := NULL,
        p_notes := 'Pedido web ' || v_order.order_number,
        p_created_by := v_user_id,
        p_reference_invoice_id := NULL,
        p_items := (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'product_id', product_id,
            'product_name', product_name,
            'product_sku', product_sku,
            'quantity', quantity,
            'unit_price_cents', unit_price_cents,
            'discount_percent', 0,
            'discount_cents', 0,
            'line_total_cents', line_total_cents,
            'tax_affectation', COALESCE(tax_affectation, 'gravado'),
            'igv_cents', igv_cents
        )), '[]'::jsonb) FROM public.store_order_items WHERE order_id = p_order_id),
        p_sales_channel := 'web_public',
        p_source_order_id := p_order_id
    );

    UPDATE public.store_orders
    SET status = 'completed', updated_at = now(), stock_branch_id = v_stock_branch_id
    WHERE id = p_order_id
      AND status = 'processing';

    RETURN v_invoice_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_stock(
    p_organization_id uuid,
    p_product_id uuid,
    p_branch_id uuid,
    p_movement_type text,
    p_quantity integer,
    p_notes text,
    p_created_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_movement_id UUID;
    v_stock_branch_id UUID;
BEGIN
    IF p_created_by IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_created_by AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Usuario no pertenece a la organizacion';
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0';
    END IF;

    SELECT public.resolve_stock_branch(p_branch_id) INTO v_stock_branch_id;

    IF v_stock_branch_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.branches
        WHERE id = p_branch_id AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Sede no pertenece a la organizacion';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.products
        WHERE id = p_product_id AND organization_id = p_organization_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Producto no pertenece a la organizacion';
    END IF;

    IF p_movement_type IN ('in', 'return') THEN
        INSERT INTO public.branch_stock (branch_id, product_id, stock, min_stock)
        VALUES (v_stock_branch_id, p_product_id, p_quantity, 0)
        ON CONFLICT (branch_id, product_id)
        DO UPDATE SET stock = public.branch_stock.stock + p_quantity;
    ELSIF p_movement_type = 'out' THEN
        UPDATE public.branch_stock
        SET stock = stock - p_quantity
        WHERE branch_id = v_stock_branch_id AND product_id = p_product_id AND stock >= p_quantity;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Stock insuficiente';
        END IF;
    ELSIF p_movement_type = 'adjustment' THEN
        INSERT INTO public.branch_stock (branch_id, product_id, stock, min_stock)
        VALUES (v_stock_branch_id, p_product_id, p_quantity, 0)
        ON CONFLICT (branch_id, product_id)
        DO UPDATE SET stock = public.branch_stock.stock + p_quantity;
    END IF;

    INSERT INTO public.stock_movements (
        organization_id, product_id, branch_id, sale_branch_id, movement_type,
        quantity, reference_type, source_channel, notes, created_by
    ) VALUES (
        p_organization_id, p_product_id, v_stock_branch_id, p_branch_id, p_movement_type,
        ABS(p_quantity), 'manual', 'manual_adjustment', p_notes, p_created_by
    ) RETURNING id INTO v_movement_id;

    RETURN v_movement_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_stock(
    p_organization_id uuid,
    p_product_id uuid,
    p_from_branch_id uuid,
    p_to_branch_id uuid,
    p_quantity integer,
    p_notes text,
    p_created_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_movement_id UUID;
BEGIN
    IF p_created_by IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_created_by AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Usuario no pertenece a la organizacion';
    END IF;

    IF p_from_branch_id = p_to_branch_id THEN
        RAISE EXCEPTION 'Las sedes de origen y destino deben ser diferentes';
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.branches
        WHERE id IN (p_from_branch_id, p_to_branch_id)
          AND stock_source_branch_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Las sedes espejo no manejan stock fisico. Transfiere desde o hacia la sede fisica de stock.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.branches
        WHERE id = p_from_branch_id AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Sede de origen no pertenece a la organizacion';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.branches
        WHERE id = p_to_branch_id AND organization_id = p_organization_id
    ) THEN
        RAISE EXCEPTION 'Sede de destino no pertenece a la organizacion';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.products
        WHERE id = p_product_id AND organization_id = p_organization_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Producto no pertenece a la organizacion';
    END IF;

    UPDATE public.branch_stock
    SET stock = stock - p_quantity
    WHERE branch_id = p_from_branch_id
      AND product_id = p_product_id
      AND stock >= p_quantity;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock insuficiente en la sede de origen';
    END IF;

    INSERT INTO public.branch_stock (branch_id, product_id, stock, min_stock)
    VALUES (p_to_branch_id, p_product_id, p_quantity, 0)
    ON CONFLICT (branch_id, product_id)
    DO UPDATE SET stock = public.branch_stock.stock + p_quantity;

    INSERT INTO public.stock_movements (
        organization_id, product_id, branch_id, movement_type,
        quantity, reference_type, transfer_to_branch_id, source_channel, notes, created_by
    ) VALUES (
        p_organization_id, p_product_id, p_from_branch_id, 'transfer_out',
        p_quantity, 'manual', p_to_branch_id, 'stock_transfer', p_notes, p_created_by
    ) RETURNING id INTO v_movement_id;

    INSERT INTO public.stock_movements (
        organization_id, product_id, branch_id, movement_type,
        quantity, reference_type, transfer_to_branch_id, source_channel, notes, created_by
    ) VALUES (
        p_organization_id, p_product_id, p_to_branch_id, 'transfer_in',
        p_quantity, 'manual', p_from_branch_id, 'stock_transfer', p_notes, p_created_by
    );

    RETURN v_movement_id;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_invoices_stock_branch_id ON public.invoices(stock_branch_id);
CREATE INDEX IF NOT EXISTS idx_invoices_sales_channel ON public.invoices(sales_channel);
CREATE INDEX IF NOT EXISTS idx_invoices_source_order_id ON public.invoices(source_order_id);
CREATE INDEX IF NOT EXISTS idx_store_orders_stock_branch_id ON public.store_orders(stock_branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_sale_branch_id ON public.stock_movements(sale_branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_source_channel ON public.stock_movements(source_channel);

GRANT EXECUTE ON FUNCTION public.resolve_stock_branch(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.create_invoice_with_items(
    uuid, text, integer, text, text, uuid,
    bigint, bigint, bigint, bigint, bigint, numeric,
    bigint, bigint, text, uuid, text, uuid, uuid, jsonb, text, uuid
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_store_order(
    text, text, text, text, text, text, uuid, text, text, text, text, text, jsonb
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_store_order(uuid) TO authenticated;
