DO $migration$
DECLARE
  definition text;
  function_id regprocedure := 'public.create_credit_note(uuid,uuid,jsonb,text,text,uuid,uuid,text)'::regprocedure;
BEGIN
  SELECT pg_get_functiondef(function_id) INTO definition;
  IF position('''credit_note.create'', ''invoice'', v_invoice_id::TEXT' IN definition) > 0 THEN
    EXECUTE replace(
      definition,
      '''credit_note.create'', ''invoice'', v_invoice_id::TEXT',
      '''credit_note.create'', ''invoice'', v_invoice_id'
    );
  ELSIF position('''credit_note.create'', ''invoice'', v_invoice_id,' IN definition) = 0 THEN
    RAISE EXCEPTION 'Unexpected create_credit_note audit definition';
  END IF;
END;
$migration$;
