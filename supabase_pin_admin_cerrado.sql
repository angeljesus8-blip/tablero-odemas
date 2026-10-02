-- ============================================================
--  verificar_pin_admin, CERRADA
--  2-oct-2026 · va DESPUÉS de todos los demás
-- ============================================================
--
--  `verificar_pin_admin(p_store_id, p_pin)` decía true si el PIN era el `admin_pin`
--  de la tienda o, cuando no lo tenía, SU NÚMERO (`coalesce(nullif(admin_pin,''),
--  store_id)`), y la puede llamar cualquiera con la clave publicable. Era un
--  oráculo: servía para comprobar PINes de Admin a ciegas, tienda por tienda, sin
--  límite de intentos, y el número de tienda funcionaba como PIN por defecto.
--
--  Nadie la usa: Admin dejó de pedir PIN (ahora manda quien `admin_de` reconoce
--  por sesión o por número de empleado), y `admin.html` ya borra el `admin_pin`
--  que quedara en el dispositivo. Mismo trato que `login_asesor`
--  (supabase_pin_cerrado.sql): la función SIGUE existiendo, con la misma firma,
--  y siempre contesta false.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.verificar_pin_admin(p_store_id text, p_pin text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT false;
$$;

REVOKE ALL ON FUNCTION public.verificar_pin_admin(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.verificar_pin_admin(text, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- COMPROBAR:  SELECT public.verificar_pin_admin('9999', '9999');   -- Esperado: false
