-- ============================================================
-- Cada quien ve SU comisión — Odemás multi-tienda, 20-sep-2026
-- ============================================================
-- Portado de la 1217, donde esto se cerró el 6-sep (`supabase_comisiones_
-- privadas.sql`) y se completó el 15-sep (`supabase_comisiones_gerente_
-- correo.sql`). Aquí van los dos pasos JUNTOS: esta base nunca tuvo el
-- intermedio, así que no hay nada que migrar en dos tiempos.
--
-- QUÉ ESTÁ MAL HOY
--
-- `comisiones_lista(p_store)` no pide NADA salvo el número de tienda y está
-- concedida a `anon`. La clave publicable viaja dentro de comisiones.html, en
-- un repo público. O sea que cualquiera puede volcar el sueldo del equipo
-- entero —nombre, venta, garantías, importe— con un curl, sin sesión y sin
-- número, y aquí además de CUALQUIER TIENDA DE LA RED: basta con cambiar el
-- `p_store`. En la 1217 era una tienda; aquí son todas.
--
-- QUÉ HACE ESTE ARCHIVO
--
-- Crea la versión de tres argumentos, que filtra por QUIÉN MIRA, y revoca la
-- vieja. No toca ni un importe: solo quién los ve.
--
-- Ven al equipo entero, por dos caminos:
--   · quien entró con el CORREO de la tienda y manda en ella  -> admin_de()
--   · gerente o subgerente, por su NÚMERO                     -> puede_gestionar_()
-- Cualquier otra persona ve una sola fila: la suya.
-- Y sin número y sin sesión no se devuelve nada — «no sé quién eres» no puede
-- significar «toma todo».
--
-- Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 0 · Que no falte ninguna pieza ────────────────────────────
-- Si algún ayudante no está, esto para AQUÍ con un mensaje en vez de dejar la
-- función a medio crear. Los tres existen ya en esta base; la comprobación es
-- para el día en que se pegue sobre una tienda recién montada.
DO $chk$
DECLARE faltan text := '';
BEGIN
  IF to_regprocedure('public.admin_de(text)')              IS NULL THEN faltan := faltan || ' admin_de(text)'; END IF;
  IF to_regprocedure('public.puede_gestionar_(text,text)') IS NULL THEN faltan := faltan || ' puede_gestionar_(text,text)'; END IF;
  IF to_regprocedure('public.escritura_ok_(text,text)')    IS NULL THEN faltan := faltan || ' escritura_ok_(text,text)'; END IF;
  IF faltan <> '' THEN
    RAISE EXCEPTION 'Faltan funciones antes de pegar esto:%. Pega primero supabase_TODO.sql (admin_de) y supabase_venta_editar.sql (puede_gestionar_).', faltan;
  END IF;
END
$chk$;


-- ── 1 · La versión que filtra ─────────────────────────────────
-- Firma NUEVA de tres argumentos, ninguno con DEFAULT, para que conviva con la
-- vieja sin que PostgREST dude entre las dos: se llaman por nombre de
-- argumento, y {p_store} solo casa con la vieja y {p_store,p_token,p_empno}
-- solo con esta. Sin esto, una sobrecarga ambigua responde PGRST203 y la
-- pantalla se queda sin comisiones para TODOS.
--
-- `alcance` y `gar_pct` SÍ pueden pasar de 100 — hay 30 días de ventana para
-- comprar el seguro. Si alguien mete aquí un LEAST(...,100) «para que se vea
-- bien», estará borrando trabajo hecho de verdad. (Se conserva tal cual de la
-- función anterior; esto no cambia ni un número, solo QUIÉN los ve.)
CREATE OR REPLACE FUNCTION public.comisiones_lista(
  p_store text,
  p_token text,
  p_empno text
)
RETURNS TABLE (empno text, nombre text, puesto text, venta numeric,
               ppto_pct numeric, alcance numeric, gar_pct numeric,
               gar_pzas integer, gar_elegible integer, gar_monto numeric,
               periodo text, periodo_gar text, actualizado timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
  SELECT k.empno, k.nombre, k.puesto, k.venta, k.ppto_pct, k.alcance,
         k.gar_pct, k.gar_pzas, k.gar_elegible, k.gar_monto,
         k.periodo, k.periodo_gar, k.updated_at
  FROM public.comisiones k
  WHERE k.store_id = p_store
    -- El token sigue siendo obligatorio para todos, también para quien manda:
    -- es lo que identifica a la TIENDA. Sin él no se devuelve nada.
    AND public.escritura_ok_(p_store, p_token)
    AND (
      -- Quien entró con su correo y administra ESTA tienda. Es el dueño, que no
      -- tiene número que enseñar. `admin_de` mira `auth.uid()`, así que con la
      -- clave publicable responde que no: esto no reabre lo que se cierra abajo.
      -- SECURITY DEFINER cambia de dueño los permisos, no el JWT de quien llama.
      --
      -- Ojo con el multi-tienda: `admin_de(p_store)` pregunta por la tienda que
      -- se pide, no por «alguna». El dueño de una tienda no ve las comisiones de
      -- la de al lado aunque tenga sesión abierta.
      public.admin_de(p_store)

      -- Gerente y subgerente, por su número. Se comprueba contra `empleados`
      -- —activo y puesto—, no contra lo que diga el teléfono.
      OR public.puede_gestionar_(p_store, nullif(trim(coalesce(p_empno,'')), ''))

      -- Y cualquier otra persona, su propia fila. El `nullif` es lo que impide
      -- que venir sin número case con una fila de empno vacío.
      OR k.empno = nullif(trim(coalesce(p_empno,'')), '')
    )
  ORDER BY k.venta DESC NULLS LAST;
$fn$;

REVOKE ALL      ON FUNCTION public.comisiones_lista(text,text,text) FROM public;
GRANT EXECUTE   ON FUNCTION public.comisiones_lista(text,text,text) TO anon, authenticated;

COMMENT ON FUNCTION public.comisiones_lista(text,text,text) IS
  'Comisiones de la tienda filtradas por quien mira: el dueno por correo y '
  'gerente/subgerente por numero ven el equipo entero, cualquier otro solo su '
  'fila, y sin token o sin numero no se devuelve nada. Sustituye a '
  'comisiones_lista(text), que las daba todas —y de cualquier tienda— a '
  'cualquiera con la clave publicable.';


-- ── 2 · Cerrar la puerta vieja ────────────────────────────────
-- Esto apaga `comisiones_lista(p_store)`: la que devuelve el equipo entero sin
-- pedir nada. SE PEGA JUNTO CON LO DE ARRIBA. Pegar el SQL tiene que bastar
-- para que el cambio valga; no puede quedar dependiendo de que cada quien
-- actualice su celular.
REVOKE ALL ON FUNCTION public.comisiones_lista(text) FROM anon, authenticated;

-- Se REVOCA y no se borra: un DROP se lleva por delante lo que dependa de ella,
-- y volver a concederla si algo sale mal es una línea:
--   GRANT EXECUTE ON FUNCTION public.comisiones_lista(text) TO anon, authenticated;
--
-- ⚠️ ANTES DE PEGAR ESTO, la app tiene que estar publicada con el cliente que
-- sabe llamar las dos firmas (comisiones.html y admin.html, 20-sep-2026). Un
-- celular con la versión anterior solo sabe llamar la vieja: al revocarla verá
-- la pantalla vacía hasta que se actualice. Lo único que NO se puede cerrar
-- desde aquí es la copia que cada teléfono ya tiene guardada de antes; esa se
-- borra sola en cuanto esa persona abre la app actualizada.


-- ============================================================
-- COMPROBAR  (cambia <tienda>, <token> y los números por los reales)
-- ============================================================
--
-- Los puntos 1 y 2 NO se pueden comprobar desde el SQL Editor: ahí `auth.uid()`
-- es la sesión del editor, no la de la app, que es donde vive el caso.
--
-- 1) En la app, con CORREO Y CONTRASEÑA de la tienda: Comisiones enseña
--    «👥 Equipo — N integrantes», no «entra con tu número de empleado».
--
-- 2) En la app, con el NÚMERO de un asesor: una sola tarjeta, la suya.
--
-- 3) Sin sesión y sin número — el agujero que se cierra hoy:
--      select count(*) from public.comisiones_lista('<tienda>', '<token>', '');
--      -- espera 0
--
-- 4) El gerente por su número sigue viendo a todos:
--      select count(*) from public.comisiones_lista('<tienda>', '<token>', '<empno-gerente>');
--      -- espera el número de personas con comisión cargada
--
-- 5) El asesor por su número, solo la suya:
--      select empno from public.comisiones_lista('<tienda>', '<token>', '<empno-asesor>');
--      -- espera EXACTAMENTE una fila, y con su propio número
--
-- 6) Con el token equivocado, nada — ni para quien manda:
--      select count(*) from public.comisiones_lista('<tienda>', 'no-es', '<empno-gerente>');
--      -- espera 0
--
-- 7) Un número que no es de nadie no abre nada:
--      select count(*) from public.comisiones_lista('<tienda>', '<token>', '999999');
--      -- espera 0
--
-- 8) MULTI-TIENDA — el gerente de una tienda pidiendo la de al lado:
--      select count(*) from public.comisiones_lista('<otra-tienda>', '<token-de-la-tuya>', '<empno-gerente>');
--      -- espera 0  (el token es de la tienda, y `escritura_ok_` los cruza)
--
-- 9) Y la puerta vieja, cerrada de verdad. Esto tiene que FALLAR con
--    «permission denied for function comisiones_lista»:
--      set role anon;
--      select count(*) from public.comisiones_lista('<tienda>');
--      reset role;
