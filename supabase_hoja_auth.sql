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
       (hoja_auth IS NOT NULL AND hoja_auth <> '') AS tiene_hoja_auth
FROM public.tiendas
ORDER BY store_id;

-- ------------------------------------------------------------
-- PASO 2 · Las columnas, por si alguna falta (otra tienda nueva)
-- ------------------------------------------------------------
-- `sheet_url` (el link a la hoja de Google) ya no se anade: no hay hoja.
ALTER TABLE public.tiendas
  ADD COLUMN IF NOT EXISTS hoja_auth text;

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

/* Lo que el login NO nombra aqui llega VACIO al telefono, y lo que dependa de
   ese campo se apaga sin dar un error. Paso con `hoja_auth`: el gerente lo tenia
   puesto en Admin, el cliente lo leia, y el boton de las ventas del dia estuvo
   oculto para todos porque el servidor no lo devolvia.

   Los comentarios van arriba del CREATE y no entre la firma y el RETURNS TABLE:
   `r_cadenas` empareja los dos y solo admite un salto de linea, asi que un
   comentario en medio la ciega. */
DROP FUNCTION IF EXISTS public.login_asesor(text);

CREATE FUNCTION public.login_asesor(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb, gas_token text,
               hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         to_jsonb(t.vendedores), t.gas_token,
         t.hoja_auth
  FROM public.tiendas t
  WHERE coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND p_pin = coalesce(nullif(t.asesor_pin, ''), t.store_id)
  LIMIT 1;
$$;

DROP FUNCTION IF EXISTS public.login_empleado(text);

CREATE FUNCTION public.login_empleado(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb,
               emp_no text, emp_nombre text, emp_puesto text, emp_admin boolean,
               gas_token text, hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         to_jsonb(t.vendedores),
         e.empno, e.nombre, e.puesto, e.admin,
         t.gas_token, t.hoja_auth
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
-- Una fila por tienda registrada. En una base recién montada no hay ninguna
-- todavía: cero filas aquí es lo normal, y el alta se hace desde la app
-- (menú → Registrar tienda).
SELECT t.store_id,
  (SELECT count(*) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)))
    AS el_login_responde,
  (SELECT (l.hoja_auth IS NOT NULL) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)) l)
    AS ya_entrega_hoja_auth,
  (SELECT (l.gas_token IS NOT NULL) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)) l)
    AS sigue_trayendo_token
FROM public.tiendas t ORDER BY t.store_id;

/* Y que el login por número de empleado tampoco se haya roto.

   Dice en palabras si no hay a quién preguntarle: con la tabla `empleados`
   vacía, la versión anterior devolvía «0, 0, 0» y eso se lee igual que «los
   tres empleados que entran perdieron el token», que es un incendio. Una
   comprobación que devuelve lo mismo cuando todo va bien y cuando todo va mal
   no está comprobando nada. */
SELECT CASE
    WHEN count(*) = 0
      THEN 'todavía no hay nadie dado de alta — normal en una base nueva; '
           'se registran en Admin → Equipo'
    WHEN count(*) FILTER (WHERE (SELECT l.gas_token FROM public.login_empleado(e.empno) l) IS NOT NULL) = count(*)
      THEN 'los ' || count(*) || ' entran y todos reciben su clave de escritura'
    ELSE '⚠ ' || count(*) FILTER (WHERE (SELECT l.gas_token FROM public.login_empleado(e.empno) l) IS NULL)
         || ' de ' || count(*) || ' entran SIN clave de escritura: la app se '
         || 'les ve entera y no guarda nada'
  END AS login_por_numero
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

   FALTA: que la persona autorizada SALGA y vuelva a ENTRAR en Captura de
   Series. La sesión
   se guarda en el aparato al entrar; con la vieja sigue sin hoja_auth y el
   botón sigue oculto aunque aquí ya esté todo bien.
   ============================================================ */
