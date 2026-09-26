-- ============================================================
--  DAR DE BAJA (Y REPARTIR PERMISOS) TAMBIÉN CON LA SESIÓN DE CORREO
--  26-sep-2026
-- ============================================================
--
--  Qué lo trae
--  -----------
--  Ángel, en Admin → 👥 Equipo de odemás: «no me permite dar de baja a algún
--  miembro, me dice que no es mi tienda». La respuesta era «no administras esta
--  tienda», de `empleado_permiso` (supabase_equipo_por_numero.sql).
--
--  Esa función decide con `puede_admin(tienda, NÚMERO DE EMPLEADO)`, y el
--  número lo manda la pantalla desde `odemas_empleado`. El gerente que entra
--  con el CORREO de la tienda no trae número —es la cuenta dueña, no una ficha
--  del equipo—, así que llegaba vacío y la base le negaba lo que la pantalla le
--  estaba ofreciendo: Admin le abría, la lista se veía y el botón fallaba.
--  Es el mismo patrón de siempre (memoria «gerente sin ficha»): la misma
--  persona, dos puertas, distinto resultado.
--
--  En la 1217 no pasa: allá la baja escribe la tabla con la sesión y la RLS.
--  Aquí se hizo por función el 2-sep-2026 para que el SUBGERENTE, que entra con
--  su número y sin correo, también pudiera — y se quedó fuera el otro camino.
--
--  Qué cambia
--  ----------
--  Manda quien cumpla CUALQUIERA de los dos:
--    · su número de empleado tiene Admin en esta tienda (`puede_admin`), o
--    · su sesión de correo manda en esta tienda (`admin_de`: dueña de la
--      tienda, o ficha activa con Admin atada a esa cuenta). Lo dice el
--      servidor con auth.uid(), no el navegador.
--  La clave de escritura se sigue pidiendo igual, antes que nada.
--
--  «No quitarte a ti mismo el acceso» ahora también mira la sesión: la ficha
--  atada a tu cuenta (user_id) cuenta como tú aunque no mandes número.
--
--  Misma firma que antes: la app no cambia y no hay que publicar nada.
--  Se puede pegar varias veces.
-- ============================================================

CREATE OR REPLACE FUNCTION public.empleado_permiso(
  p_store text, p_token text, p_quien text,
  p_id bigint, p_campo text, p_valor boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_obj record; v_admins int; v_uid uuid := auth.uid();
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin permiso de escritura');
  END IF;
  -- Por nombre, por lo mismo que en `equipo_lista`: al reves niega en silencio.
  -- El numero O la sesion de correo; ver la cabecera.
  IF NOT (public.puede_admin(p_store_id => p_store, p_empno => coalesce(p_quien, ''))
          OR (v_uid IS NOT NULL AND public.admin_de(p_store_id => p_store))) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no administras esta tienda');
  END IF;
  IF p_campo NOT IN ('admin', 'ventas_dia', 'activo') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'campo no permitido: ' || coalesce(p_campo,'(vacío)'));
  END IF;

  SELECT * INTO v_obj FROM public.empleados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'esa persona no es de esta tienda');
  END IF;

  -- Uno mismo: por su numero, o por la ficha atada a su cuenta de correo.
  IF (v_obj.empno = p_quien OR (v_uid IS NOT NULL AND v_obj.user_id = v_uid))
     AND p_campo IN ('admin','activo') AND p_valor = false THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'no puedes quitarte a ti mismo ese acceso; que lo haga otra persona con Admin');
  END IF;

  IF p_campo IN ('admin','activo') AND p_valor = false THEN
    SELECT count(*) INTO v_admins FROM public.empleados
     WHERE store_id = p_store AND admin = true AND activo = true;
    IF v_admins <= 1 AND v_obj.admin AND v_obj.activo THEN
      RETURN jsonb_build_object('ok', false,
        'error', 'es el último acceso a Admin de la tienda: da Admin a alguien más antes de quitárselo');
    END IF;
  END IF;

  IF    p_campo = 'admin'      THEN UPDATE public.empleados SET admin      = p_valor WHERE id = p_id;
  ELSIF p_campo = 'ventas_dia' THEN UPDATE public.empleados SET ventas_dia = p_valor WHERE id = p_id;
  ELSE                              UPDATE public.empleados SET activo     = p_valor WHERE id = p_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'campo', p_campo, 'valor', p_valor,
                            'quien', v_obj.nombre);
END $fn$;

REVOKE ALL ON FUNCTION public.empleado_permiso(text,text,text,bigint,text,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.empleado_permiso(text,text,text,bigint,text,boolean)
  TO anon, authenticated;

-- COMPROBAR: es lo último, así que es lo que enseña el editor. Sin clave de
-- escritura tiene que contestar lo de siempre, y la función tiene que ser una.
-- Esperado: una fila, «sin permiso de escritura» y versiones = 1.
SELECT public.empleado_permiso('9999', 'clave-falsa', '', 0, 'activo', false) ->> 'error' AS respuesta,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'empleado_permiso') AS versiones;
