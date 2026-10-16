ALTER TABLE public.invoices
  ALTER COLUMN issue_date SET DEFAULT ((now() AT TIME ZONE 'America/Lima')::date);
