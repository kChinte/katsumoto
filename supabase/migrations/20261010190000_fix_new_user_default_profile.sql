CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_org_id uuid;
    v_role text;
BEGIN
    v_org_id := NULLIF(new.raw_user_meta_data->>'organization_id', '')::uuid;

    IF v_org_id IS NULL THEN
        SELECT id
        INTO v_org_id
        FROM public.organizations
        ORDER BY created_at, id
        LIMIT 1;
    END IF;

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No existe una organizacion para crear el perfil del usuario';
    END IF;

    v_role := NULLIF(new.raw_user_meta_data->>'role', '');

    IF v_role IS NULL THEN
        SELECT CASE
            WHEN EXISTS (
                SELECT 1
                FROM public.profiles
                WHERE organization_id = v_org_id
            ) THEN 'cashier'
            ELSE 'owner'
        END
        INTO v_role;
    END IF;

    INSERT INTO public.profiles (id, email, full_name, organization_id, role, is_active)
    VALUES (
        new.id,
        new.email,
        COALESCE(new.raw_user_meta_data->>'full_name', new.email),
        v_org_id,
        v_role,
        true
    )
    ON CONFLICT (id) DO UPDATE SET
        email = excluded.email,
        full_name = excluded.full_name,
        organization_id = excluded.organization_id,
        role = excluded.role,
        is_active = excluded.is_active,
        updated_at = now();

    RETURN new;
END;
$$;
