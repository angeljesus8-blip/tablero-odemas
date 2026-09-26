-- ============================================================
--  LLAVES HACIA `tiendas` QUE FALTABAN
--  26-sep-2026
-- ============================================================
--
--  Qué lo trae
--  -----------
--  Al borrar las tiendas de prueba 1216 y 1218 se vio que `empleados` e
--  `invitaciones` NO tenían llave hacia `tiendas`. Las otras quince tablas sí,
--  con ON DELETE CASCADE, así que borrar una tienda se llevaba sus ventas, su
--  inventario y sus fotos… y dejaba a su EQUIPO en la base, huérfano. Y no
--  daba ningún error: un DELETE de la tienda salía «bien».
--
--  Un empleado huérfano no es solo basura: las fichas van por store_id, así
--  que si alguien vuelve a dar de alta ese mismo número de tienda, hereda un
--  equipo que no dio de alta — con sus números y sus permisos de Admin.
--
--  Qué hace
--  --------
--  · empleados.store_id      → tiendas, ON DELETE CASCADE.
--  · invitaciones.usado_store → tiendas, ON DELETE CASCADE. Se llena en
--    `alta_tienda` DESPUÉS de insertar la tienda, así que siempre existe.
--
--  Qué NO hace, a propósito
--  ------------------------
--  · invitaciones.store_id NO lleva llave. Una invitación se crea ANTES de que
--    su tienda exista —es lo que la abre—; con llave, `invitacion_nueva` no
--    podría invitar a nadie. Una invitación sin usar de una tienda borrada se
--    queda, y es inofensiva: vence sola a los 30 días.
--
--  Orden dentro de `alta_tienda` (supabase_alta_por_invitacion.sql), comprobado
--  antes de poner las llaves: 1) INSERT tiendas, 2) INSERT empleados,
--  3) UPDATE invitaciones. Las dos llaves se cumplen en ese orden. Admin da de
--  alta empleados por RLS, que ya exige que la tienda exista.
--
--  Se puede pegar varias veces: cada llave se quita antes de ponerla.
--  Si hay huérfanos, el ADD CONSTRAINT se detiene con error y no cambia nada
--  (ver el paso MIRAR en 05-Analisis/odemas_llaves_tienda_MIRAR.sql).
-- ============================================================

ALTER TABLE public.empleados
  DROP CONSTRAINT IF EXISTS empleados_store_id_fkey;
ALTER TABLE public.empleados
  ADD CONSTRAINT empleados_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES public.tiendas(store_id) ON DELETE CASCADE;

ALTER TABLE public.invitaciones
  DROP CONSTRAINT IF EXISTS invitaciones_usado_store_fkey;
ALTER TABLE public.invitaciones
  ADD CONSTRAINT invitaciones_usado_store_fkey
  FOREIGN KEY (usado_store) REFERENCES public.tiendas(store_id) ON DELETE CASCADE;

-- COMPROBAR: es lo último, así que es el resultado que enseña el editor.
-- Esperado: dos filas, las dos «borra en cascada».
SELECT cl.relname || '.' || a.attname AS columna,
       CASE k.confdeltype WHEN 'c' THEN 'borra en cascada' WHEN 'n' THEN 'pone NULL'
                          ELSE 'bloquea' END AS al_borrar_la_tienda
  FROM pg_constraint k
  JOIN pg_class cl    ON cl.oid = k.conrelid
  JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY(k.conkey)
 WHERE k.contype = 'f' AND k.confrelid = 'public.tiendas'::regclass
   AND cl.relname IN ('empleados', 'invitaciones')
 ORDER BY 1;
