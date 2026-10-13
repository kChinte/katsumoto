ALTER TABLE public.sunat_config
  ADD COLUMN IF NOT EXISTS clave_sol text,
  ADD COLUMN IF NOT EXISTS certificado_password text;

UPDATE public.sunat_config
SET
  clave_sol = COALESCE(clave_sol, clave_sol_encrypted),
  certificado_password = COALESCE(certificado_password, certificado_password_encrypted)
WHERE clave_sol IS NULL
   OR certificado_password IS NULL;

NOTIFY pgrst, 'reload schema';
