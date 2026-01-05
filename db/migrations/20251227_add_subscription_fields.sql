-- =====================================================
-- AGREGAR CAMPOS DE SUSCRIPCIÓN A PROFILES
-- =====================================================

-- Agregar columnas para gestionar suscripciones
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS subscription_start TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS subscription_end TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS subscription_cancelled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS epayco_subscription_id TEXT,
ADD COLUMN IF NOT EXISTS last_payment_date TIMESTAMP WITH TIME ZONE;

-- Índice para búsquedas rápidas de suscripciones activas
CREATE INDEX IF NOT EXISTS idx_profiles_subscription_end 
ON public.profiles(subscription_end) 
WHERE subscription_end IS NOT NULL;

-- Índice para suscripciones de ePayco
CREATE INDEX IF NOT EXISTS idx_profiles_epayco_subscription 
ON public.profiles(epayco_subscription_id) 
WHERE epayco_subscription_id IS NOT NULL;

-- Comentarios
COMMENT ON COLUMN public.profiles.subscription_start IS 'Fecha de inicio de la suscripción premium';
COMMENT ON COLUMN public.profiles.subscription_end IS 'Fecha de fin de la suscripción premium';
COMMENT ON COLUMN public.profiles.subscription_cancelled IS 'Indica si el usuario canceló la renovación automática';
COMMENT ON COLUMN public.profiles.epayco_subscription_id IS 'ID de suscripción en ePayco';
COMMENT ON COLUMN public.profiles.last_payment_date IS 'Fecha del último pago recibido';
