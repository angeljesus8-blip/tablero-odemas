-- ============================================================
-- El login debe entregar hoja_auth y sheet_url
-- APLICADO EN PRODUCCIÓN el 2-ago-2026. Ver "Lo que salió" abajo.
-- ============================================================
--
-- Qué estaba roto
-- ---------------
-- Captura de Series decide quién ve las ventas del día así:
--
--     const DESCARGA_AUTORIZADA = (_cfgCS && _cfgCS.hoja_auth) || '';
--     const ok = currentVend === DESCARGA_AUTORIZADA;
--
-- La columna `hoja_auth` existía y ya traía el nombre correcto, pero
-- login_asesor devolvía solo (store_id, nombre, ciudad, gas_url,
-- vendedores, gas_token). El dato estaba bien guardado y nunca salía:
-- llegaba undefined, se guardaba como '', y la comparación era falsa
-- para todos. El botón estuvo oculto para todo el mundo —incluida la
-- única persona que lo usa— desde el 1-ago.
--
-- El 1-ago se corrigió el nombre del campo en el cliente y se dio por
-- cerrado. El cliente pedía bien un dato que el servidor nunca mandó.
--
-- Un cambio no termina hasta probarlo de punta a punta (MAPA.md).
--
-- ------------------------------------------------------------
-- PASO 1 · Ver cómo está antes de tocar
-- ------------------------------------------------------------
SELECT store_id, nombre,
       (hoja_auth IS NOT NULL AND hoja_auth <> '') AS tiene_hoja_auth,
       (sheet_url IS NOT NULL AND sheet_url <> '') AS tiene_sheet_url
FROM public.tiendas
ORDER BY store_id;

-- ------------------------------------------------------------
-- PASO 2 · Las columnas, por si alguna falta (otra tienda nueva)
-- ------------------------------------------------------------
ALTER TABLE public.tiendas
  ADD COLUMN IF NOT EXISTS hoja_auth text,
  ADD COLUMN IF NOT EXISTS sheet_url text;

COMMENT ON COLUMN public.tiendas.hoja_auth IS
  'Nombre EXACTO del vendedor que puede ver las ventas del día en Captura de '
  'Series, tal como aparece en la lista de vendedores. Se compara letra por '
  'letra: una tilde o un espacio de más y deja de funcionar. Vacío = nadie.';

-- ------------------------------------------------------------
-- PASO 3 · Comprobar que el nombre coincide con la lista
-- ------------------------------------------------------------
-- Esto es lo que de verdad decide si el botón aparece. `currentVend` sale
-- de la lista `vendedores`, y se compara con `===` contra `hoja_auth`: si
-- difieren en una tilde, el botón no sale y nada avisa.
--
-- OJO: `vendedores` es jsonb, NO text[]. `unnest()` truena con
-- "function unnest(jsonb) does not exist"; va jsonb_array_elements_text().
SELECT store_id,
       (SELECT count(*) FROM jsonb_array_elements_text(vendedores) v
        WHERE v = hoja_auth)                            AS coincide_exacto,
       (SELECT count(*) FROM jsonb_array_elements_text(vendedores) v) AS total_vendedores
FROM public.tiendas
WHERE store_id = '1217';

-- coincide_exacto debe ser 1. Si es 0, el nombre de hoja_auth no está en la
-- lista tal cual y hay que copiarlo de ahí, sin retocarlo a mano.

-- ------------------------------------------------------------
-- PASO 4 · Que las funciones lo entreguen  ← lo único que hacía falta
-- ------------------------------------------------------------
-- Cambia el tipo de retorno, así que CREATE OR REPLACE no basta: hay que
-- DROP primero. El cuerpo es el mismo de GAS_guardian.sql; lo único nuevo
-- son t.hoja_auth y t.sheet_url al final.
--
-- Entre el DROP y el CREATE nadie puede entrar a la app: correr de corrido.

/* `sku_reparacion` viaja desde el 24-ago-2026: es lo que deja a Captura de
   Series distinguir sola una reparacion de un accesorio al leer el ticket. El
   gerente lo tenia puesto en Admin y aun asi la deteccion estaba apagada en los
   telefonos, porque el login no lo traia.

   Un campo que no se nombra aqui llega VACIO y lo que dependa de el se apaga en
   silencio. Va escrito arriba del CREATE y no entre la firma y el RETURNS
   TABLE: `r_cadenas` empareja los dos y solo admite un salto de linea, asi que
   un comentario en medio la ciega. */
DROP FUNCTION IF EXISTS public.login_asesor(text);

CREATE FUNCTION public.login_asesor(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               gas_url text, vendedores jsonb, gas_token text,
               hoja_auth text, sheet_url text, sku_reparacion text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad, t.gas_url,
         to_jsonb(t.vendedores), t.gas_token,
         t.hoja_auth, t.sheet_url, t.sku_reparacion
  FROM public.tiendas t
  WHERE coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND p_pin = coalesce(nullif(t.asesor_pin, ''), t.store_id)
  LIMIT 1;
$$;

DROP FUNCTION IF EXISTS public.login_empleado(text);

CREATE FUNCTION public.login_empleado(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               gas_url text, vendedores jsonb,
               emp_no text, emp_nombre text, emp_puesto text, emp_admin boolean,
               gas_token text, hoja_auth text, sheet_url text, sku_reparacion text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad, t.gas_url,
         to_jsonb(t.vendedores),
         e.empno, e.nombre, e.puesto, e.admin,
         t.gas_token, t.hoja_auth, t.sheet_url, t.sku_reparacion
  FROM public.empleados e
  JOIN public.tiendas  t ON t.store_id = e.store_id
  WHERE e.activo = true
    AND coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND e.empno = p_pin
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.login_asesor(text)   FROM public;
REVOKE ALL ON FUNCTION public.login_empleado(text) FROM public;
GRANT EXECUTE ON FUNCTION public.login_asesor(text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_empleado(text) TO anon, authenticated;

-- ------------------------------------------------------------
-- PASO 5 · Comprobar que quedó, sin escribir el PIN aquí
-- ------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)))
    AS el_login_responde,
  (SELECT (l.hoja_auth IS NOT NULL) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)) l)
    AS ya_entrega_hoja_auth,
  (SELECT (l.gas_token IS NOT NULL) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)) l)
    AS sigue_trayendo_token
FROM public.tiendas t WHERE t.store_id = '1217';

-- Y que el login del gerente tampoco se haya roto:
SELECT count(*) AS empleados_que_entran,
       count(*) FILTER (WHERE (SELECT l.hoja_auth FROM public.login_empleado(e.empno) l) IS NOT NULL)
         AS con_hoja_auth,
       count(*) FILTER (WHERE (SELECT l.gas_token FROM public.login_empleado(e.empno) l) IS NOT NULL)
         AS con_token
FROM public.empleados e
WHERE e.activo = true
  AND (SELECT count(*) FROM public.login_empleado(e.empno)) = 1;

/* ============================================================
   Lo que salió al aplicarlo — 2-ago-2026
   ============================================================

   PASO 1 · La columna hoja_auth YA existía y YA traía el nombre correcto,
            y sheet_url también. O sea que nunca hubo que tocar datos: el
            único hueco era que las funciones no lo devolvían.

   PASO 3 · coincide_exacto = 1 de 5 vendedores. El nombre calza letra por
            letra con la lista, que es lo que compara el cliente.

            Aquí salió el error del propio archivo: la primera versión usaba
            unnest(vendedores) dando por hecho que era text[]. Es jsonb.
            Se corrigió arriba.

   PASO 4 · Success. No rows returned.

   PASO 5 · login_asesor  → responde 1, entrega hoja_auth, sigue con token.
            login_empleado → 5 empleados entran, los 5 con hoja_auth y token,
                             2 admins. Nada se rompió.

   FALTA: que Laura SALGA y vuelva a ENTRAR en Captura de Series. La sesión
   se guarda en el aparato al entrar; con la vieja sigue sin hoja_auth y el
   botón sigue oculto aunque aquí ya esté todo bien.
   ============================================================ */
