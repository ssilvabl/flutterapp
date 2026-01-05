-- Tabla para registrar pagos de suscripción
CREATE TABLE IF NOT EXISTS subscription_payments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    transaction_id TEXT NOT NULL UNIQUE,
    amount INTEGER NOT NULL,
    currency TEXT DEFAULT 'COP',
    payment_method TEXT,
    status TEXT NOT NULL, -- 'approved', 'rejected', 'pending'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Agregar columna subscription_cancelled a profiles si no existe
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'subscription_cancelled'
    ) THEN
        ALTER TABLE profiles ADD COLUMN subscription_cancelled BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Índices para mejorar el rendimiento
CREATE INDEX IF NOT EXISTS idx_subscription_payments_user_id ON subscription_payments(user_id);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_transaction_id ON subscription_payments(transaction_id);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_created_at ON subscription_payments(created_at DESC);

-- Políticas de seguridad para subscription_payments
ALTER TABLE subscription_payments ENABLE ROW LEVEL SECURITY;

-- Los usuarios pueden ver sus propios pagos
CREATE POLICY "Users can view their own payments"
    ON subscription_payments FOR SELECT
    USING (auth.uid() = user_id);

-- Solo el sistema puede insertar pagos (esto se manejará desde el backend/webhook)
CREATE POLICY "System can insert payments"
    ON subscription_payments FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Comentarios
COMMENT ON TABLE subscription_payments IS 'Registro de pagos de suscripciones realizados a través de ePayco';
COMMENT ON COLUMN subscription_payments.transaction_id IS 'ID de transacción único de ePayco';
COMMENT ON COLUMN subscription_payments.status IS 'Estado del pago: approved, rejected, pending';
