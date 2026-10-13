INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('sunat-documents', 'sunat-documents', false, 10485760)
ON CONFLICT (id) DO UPDATE SET
  public = excluded.public,
  file_size_limit = excluded.file_size_limit;

DROP POLICY IF EXISTS "sunat_documents_select_org" ON storage.objects;
DROP POLICY IF EXISTS "sunat_documents_insert_admin_org" ON storage.objects;
DROP POLICY IF EXISTS "sunat_documents_update_admin_org" ON storage.objects;
DROP POLICY IF EXISTS "sunat_documents_delete_admin_org" ON storage.objects;

CREATE POLICY "sunat_documents_select_org"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'sunat-documents'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.organization_id::text = (storage.foldername(name))[1]
      AND p.is_active = true
  )
);

CREATE POLICY "sunat_documents_insert_admin_org"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'sunat-documents'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.organization_id::text = (storage.foldername(name))[1]
      AND p.role IN ('owner', 'admin')
      AND p.is_active = true
  )
);

CREATE POLICY "sunat_documents_update_admin_org"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'sunat-documents'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.organization_id::text = (storage.foldername(name))[1]
      AND p.role IN ('owner', 'admin')
      AND p.is_active = true
  )
)
WITH CHECK (
  bucket_id = 'sunat-documents'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.organization_id::text = (storage.foldername(name))[1]
      AND p.role IN ('owner', 'admin')
      AND p.is_active = true
  )
);

CREATE POLICY "sunat_documents_delete_admin_org"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'sunat-documents'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.organization_id::text = (storage.foldername(name))[1]
      AND p.role IN ('owner', 'admin')
      AND p.is_active = true
  )
);
