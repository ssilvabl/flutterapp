-- Migration: 2025-12-24 - Add payments_movements table and backfill initial movements
BEGIN;

-- 1) Create table for movements
CREATE TABLE IF NOT EXISTS public.payments_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  movement_type text NOT NULL, -- 'initial', 'increment', 'reduction'
  amount numeric(12,2) NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- index
CREATE INDEX IF NOT EXISTS idx_payments_movements_payment_id ON public.payments_movements (payment_id);

-- 2) Backfill: for existing payments create an 'initial' movement with current amount
INSERT INTO public.payments_movements (payment_id, user_id, movement_type, amount, note, created_at)
SELECT id, user_id, 'initial' as movement_type, amount::numeric(12,2), 'migrated initial', created_at
FROM public.payments
WHERE id NOT IN (SELECT payment_id FROM public.payments_movements);

-- 3) (Optional) RLS for movements to only allow owners
ALTER TABLE public.payments_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS movements_select_owner ON public.payments_movements;
CREATE POLICY movements_select_owner
  ON public.payments_movements FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS movements_insert_owner ON public.payments_movements;
CREATE POLICY movements_insert_owner
  ON public.payments_movements FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS movements_delete_owner ON public.payments_movements;
CREATE POLICY movements_delete_owner
  ON public.payments_movements FOR DELETE USING (user_id = auth.uid());

COMMIT;

-- Notes:
-- After running this migration, the application will start inserting movement rows on create/adjust operations.
-- To remove the optional "migrated initial" rows later, you can filter by note or movement_type.
