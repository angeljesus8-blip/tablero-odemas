-- ============================================================
--  EL PIN DE LA TIENDA, CERRADO
--  2-oct-2026 · va DESPUÉS de todos los demás (último de la lista)
-- ============================================================
--
--  Qué lo trae
--  -----------
--  `login_asesor(p_pin)` aceptaba como PIN el NÚMERO DE LA TIENDA cuando la
--  tienda no tenía `asesor_pin` propio —`coalesce(nullif(t.asesor_pin,''),
--  t.store_id)`— y devolvía la clave de escritura (`gas_token`). Una tienda
--  nueva nace sin `asesor_pin`, así que con solo saber su número (4 dígitos,
--  nada secreto) cualquiera entraba con la clave de la tienda: leía y escribía
--  todo, y el candado de las lecturas (supabase_candado.sql) no servía de nada.
--  Comprobado el 2-oct-2026: `login_asesor('9999')` devolvió el token de la Demo.
--
--  Qué hace
--  --------
--  La función SIGUE EXISTIENDO, con la misma firma, pero ya no devuelve nada:
--  cero filas, igual que un PIN equivocado. No se borra porque `index.html` la
--  llama después de `login_empleado`, y una función que desaparece no es un
--  «PIN equivocado» sino un 404 que mandaría a la app por su camino de respaldo.
--
--  Cada persona entra con SU número de empleado (`login_empleado`), o el gerente
--  con su correo. Es lo que ya hacía el equipo: el PIN de tienda era un
--  «respaldo mientras se registra a todo el equipo».
--
--  Qué NO cubre
--  ------------
--  `login_empleado` también entrega el token a quien adivine un número de
--  empleado, y no tiene límite de intentos. Es otro paso (ver la nota del
--  proyecto), no éste.
--
--  Es seguro pegarlo más de una vez: CREATE OR REPLACE, y la guarda de abajo
--  solo comprueba la forma de la función.
-- ============================================================

BEGIN;

-- La guarda: si la función viva devuelve otra forma, `CREATE OR REPLACE` fallaría
-- a medias o, peor, se quedaría una versión distinta. Se detiene sin tocar nada.
DO $do$
DECLARE
  k   int;
  res text;
BEGIN
  SELECT count(*) INTO k FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
   WHERE s.nspname = 'public' AND p.proname = 'login_asesor';
  IF k <> 1 THEN
    RAISE EXCEPTION 'Esperaba UNA login_asesor, hay %. No se tocó nada: avísale a Claude.', k;
  END IF;

  SELECT pg_get_function_result(p.oid) INTO res
    FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
   WHERE s.nspname = 'public' AND p.proname = 'login_asesor';
  IF res <> 'TABLE(store_id text, nombre text, ciudad text, vendedores jsonb, gas_token text, hoja_auth text)' THEN
    RAISE EXCEPTION 'login_asesor devuelve (%) y esperaba otra forma. No se tocó nada.', res;
  END IF;
END $do$;

CREATE OR REPLACE FUNCTION public.login_asesor(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb, gas_token text,
               hoja_auth text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- Cero filas, siempre. Ver el encabezado.
  RETURN;
END $fn$;

REVOKE ALL ON FUNCTION public.login_asesor(text) FROM public;
GRANT EXECUTE ON FUNCTION public.login_asesor(text) TO anon, authenticated;

-- Que PostgREST vea el cambio ya, y no al rato.
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
--  COMPROBAR (yo las hago con la clave publicable, sin entrar al panel)
-- ============================================================
--
--  1 · El número de tienda ya no entra:
--      SELECT count(*) FROM public.login_asesor('9999');   -- Esperado: 0
--
--  2 · El número de empleado sigue entrando:
--      SELECT count(*) FROM public.login_empleado('100001'); -- Esperado: 1
--
--  3 · Nadie más en la base la llama por dentro (y se rompería sin avisar):
--      SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public' AND p.prosrc ~ 'login_asesor\s*\(';
--      -- Esperado: CERO filas (o solo funciones que no importen para entrar).
-- ============================================================
