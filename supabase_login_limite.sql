-- ============================================================
--  LÍMITE DE INTENTOS EN EL LOGIN POR NÚMERO DE EMPLEADO
--  2-oct-2026 · va DESPUÉS de todos los demás (último de la lista)
-- ============================================================
--
--  Qué lo trae
--  -----------
--  `login_empleado(p_pin)` recibe SOLO un número de empleado (6 dígitos,
--  consecutivos: 100001, 100002…) y devuelve la clave de escritura de su tienda.
--  No pide tienda ni contraseña y no tenía límite de intentos: con la clave
--  publicable del HTML, cualquiera podía probar números hasta acertar uno y
--  entrar a esa tienda. Comprobado el 2-oct-2026: 20 intentos malos seguidos,
--  20 respuestas 200.
--
--  Qué hace
--  --------
--  15 intentos fallidos desde la misma IP en 10 minutos → esa IP queda bloqueada
--  15 minutos. Mientras está bloqueada, `login_empleado` responde un ERROR
--  `demasiados_intentos` (no «sin filas»: la app tiene que distinguir un número
--  equivocado de un bloqueo, y no seguir probando por la ruta de respaldo).
--
--  La IP sale de `cf-connecting-ip`, no de `x-forwarded-for`. Comprobado el
--  2-oct-2026 con una sonda: `x-forwarded-for` se puede falsificar (el valor
--  mandado por el cliente queda adelante en la lista) y `cf-connecting-ip` no:
--  lo pone Cloudflare, y una petición que trae uno falso se rechaza entera
--  (error 1000). Si algún día no llega ese encabezado, NO se limita (no hay a
--  quién contárselo); contar «de todos» dejaría fuera a toda la tienda por culpa
--  de un solo atacante.
--
--  Decisiones que conviene saber
--  -----------------------------
--  · Solo se cuentan los FALLOS, y un acierto NO borra la cuenta: si lo hiciera,
--    quien tenga una cuenta propia en la misma IP la reiniciaría entre intentos.
--  · Una tienda cuyo equipo comparte wifi comparte IP: 15 tropiezos del equipo
--    entero en 10 minutos la bloquean. Es raro (el umbral es 15 y no 10 porque el teclado intenta solo a los 5 dígitos), dura 15 minutos y con datos del
--    celular se entra. Un atacante en ese mismo wifi podría bloquearla a
--    propósito; es el precio de no contar «de todos».
--  · Esto frena, no cierra: con varias IPs se puede seguir probando, más lento.
--    Cerrarlo del todo es pedir además el número de tienda o un PIN personal.
--
--  Cómo, sin copiar ningún cuerpo
--  ------------------------------
--  Igual que en supabase_candado.sql: la función viva se RENOMBRA a
--  `login_empleado_filas_` (cuerpo intacto, sin permisos) y con el nombre de
--  siempre se pone una PUERTA con la misma firma. Las columnas se copian de la
--  función viva. De `login_empleado` hay varias versiones en el repo y la que
--  manda es la de la base.
--
--  Todo va en UNA transacción, y si ya se pegó una vez se detiene sin tocar nada.
--  También borra la sonda temporal `sonda_ip()`.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.sonda_ip();

-- ── 1 · Dónde se anotan los fallos ──────────────────────────
-- Cerrada a anon y authenticated: solo la tocan las funciones de abajo.
CREATE TABLE IF NOT EXISTS public.login_intentos (
  ip text        NOT NULL,
  en timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS login_intentos_ip_en ON public.login_intentos (ip, en);
ALTER TABLE public.login_intentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.login_intentos FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.login_bloqueos (
  ip    text PRIMARY KEY,
  hasta timestamptz NOT NULL
);
ALTER TABLE public.login_bloqueos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.login_bloqueos FROM anon, authenticated;


-- ── 2 · La IP de quien llama ────────────────────────────────
CREATE OR REPLACE FUNCTION public.ip_cliente_()
RETURNS text
LANGUAGE sql STABLE SET search_path = public
AS $$
  SELECT nullif(trim(nullif(current_setting('request.headers', true), '')::json->>'cf-connecting-ip'), '');
$$;
REVOKE ALL ON FUNCTION public.ip_cliente_() FROM public, anon, authenticated;


-- ── 3 · La puerta ───────────────────────────────────────────
DO $do$
DECLARE
  k   int;
  sig text;
  res text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
              WHERE s.nspname = 'public' AND p.proname = 'login_empleado_filas_') THEN
    RAISE EXCEPTION 'login_empleado_filas_ ya existe: este archivo ya se pegó. No se tocó nada.';
  END IF;

  SELECT count(*) INTO k FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
   WHERE s.nspname = 'public' AND p.proname = 'login_empleado';
  IF k <> 1 THEN
    RAISE EXCEPTION 'Esperaba UNA login_empleado, hay %. No se tocó nada: avísale a Claude.', k;
  END IF;

  SELECT pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid)
    INTO sig, res
    FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
   WHERE s.nspname = 'public' AND p.proname = 'login_empleado';
  IF sig <> 'p_pin text' THEN
    RAISE EXCEPTION 'login_empleado tiene la firma (%), y esperaba (p_pin text). No se tocó nada.', sig;
  END IF;
  IF res !~* '^(TABLE|SETOF)' THEN
    RAISE EXCEPTION 'login_empleado devuelve % y no una tabla. No se tocó nada.', res;
  END IF;

  EXECUTE 'ALTER FUNCTION public.login_empleado(text) RENAME TO login_empleado_filas_';
  EXECUTE 'REVOKE ALL ON FUNCTION public.login_empleado_filas_(text) FROM public, anon, authenticated';

  -- Plpgsql y VOLATILE (el defecto): escribe en las tablas de intentos, y
  -- PostgREST corre las STABLE en transacción de solo lectura (25006).
  EXECUTE format($f$
    CREATE FUNCTION public.login_empleado(p_pin text)
    RETURNS %s
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
    AS $b$
    DECLARE
      v_ip text := public.ip_cliente_();
      v_n  int;
    BEGIN
      IF v_ip IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.login_bloqueos b WHERE b.ip = v_ip AND b.hasta > now()) THEN
          RAISE EXCEPTION 'demasiados_intentos' USING ERRCODE = 'P0001';
        END IF;
      END IF;

      RETURN QUERY SELECT * FROM public.login_empleado_filas_(p_pin);
      IF FOUND THEN
        RETURN;
      END IF;

      -- No entró: se anota el fallo y, si ya son 10 en 10 minutos, se bloquea.
      IF v_ip IS NOT NULL THEN
        INSERT INTO public.login_intentos (ip) VALUES (v_ip);
        SELECT count(*) INTO v_n FROM public.login_intentos i
         WHERE i.ip = v_ip AND i.en > now() - interval '10 minutes';
        IF v_n >= 15 THEN
          INSERT INTO public.login_bloqueos (ip, hasta)
          VALUES (v_ip, now() + interval '15 minutes')
          ON CONFLICT (ip) DO UPDATE SET hasta = excluded.hasta;
        END IF;
        -- Limpieza al paso, sin un cron: lo que ya no cuenta, fuera.
        DELETE FROM public.login_intentos WHERE en < now() - interval '1 day';
        DELETE FROM public.login_bloqueos WHERE hasta < now() - interval '1 day';
      END IF;
    END $b$
  $f$, res);

  EXECUTE 'REVOKE ALL ON FUNCTION public.login_empleado(text) FROM public';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.login_empleado(text) TO anon, authenticated';
END $do$;

NOTIFY pgrst, 'reload schema';

COMMIT;


-- ============================================================
--  COMPROBAR (las hago yo con la clave publicable)
-- ============================================================
--
--  1 · Un número bueno sigue entrando:   login_empleado('100001')  → 1 fila.
--  2 · Un número malo → 0 filas (no error) hasta el decimoquinto fallo.
--  3 · El 16.º intento, aunque sea con un número bueno → error `demasiados_intentos`
--      durante 15 minutos. ⚠️ Probarlo bloquea la IP desde la que se prueba.
--  4 · Solo queda UNA login_empleado y la interna sin permisos:
--      SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE')
--        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public' AND p.proname LIKE 'login_empleado%';
--      -- Esperado: login_empleado = true, login_empleado_filas_ = false.
-- ============================================================
