ALTER TABLE public.sunat_summary_log
  ADD COLUMN IF NOT EXISTS cdr_code text,
  ADD COLUMN IF NOT EXISTS cdr_description text;

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS sunat_cdr_code text,
  ADD COLUMN IF NOT EXISTS sunat_cdr_description text;

NOTIFY pgrst, 'reload schema';
