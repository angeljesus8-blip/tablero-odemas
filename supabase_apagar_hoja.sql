-- ============================================================
--  FASE 6 · la hoja deja de recibir ventas
--  17-ago-2026
-- ============================================================
--
--  Se pega DESPUÉS de desplegar v170. Antes no: mientras la app siga mandando
--  ventas al Apps Script, la comparación nocturna sigue siendo válida y vale la
--  pena tenerla.
--
--  ------------------------------------------------------------
--  POR QUÉ HAY QUE DESAGENDAR, Y NO SOLO IGNORARLO
--  ------------------------------------------------------------
--  `comparar_ventas` compara las ventas de Supabase contra las de la hoja. Desde
--  v170 la hoja no recibe ninguna, así que a partir de mañana el informe diría
--  "no cuadra" TODAS las noches, con todas las ventas del día como `sobran`.
--
--  Y sería correcto. Ese es justo el problema: un indicador permanentemente en
--  rojo por un motivo válido deja de mirarse, y cuando un día se ponga rojo de
--  verdad ya nadie lo estará leyendo. Es la misma razón por la que las entregas
--  de preventa se excluyeron de esta comparación el 7-ago.
--
--  ------------------------------------------------------------
--  LO QUE NO SE BORRA
--  ------------------------------------------------------------
--  La tabla `ventas_comparacion` se queda entera. Son los 12 días medidos
--  —del 5 al 16 de agosto, 65 ventas cotejadas una por una, cero faltantes— y
--  esa es la evidencia que autorizó apagar la hoja. Borrarla sería tirar la
--  única prueba de que la decisión estaba fundada.
--
--  Las funciones tampoco se borran: si algún día hace falta cotejar un día
--  viejo contra la hoja (que conserva su histórico), siguen ahí. Lo que se
--  quita es el trabajo automático.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Quitar el trabajo nocturno ──────────────────────────
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('comparar_ventas_diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'comparar_ventas_diario');
  END IF;
END $do$;


-- ── 2 · Dejar por escrito hasta dónde llegó la medición ─────
-- Para que dentro de seis meses se pueda saber qué significa esta tabla sin
-- tener que reconstruirlo: se llenó para decidir, y se paró al decidir.
COMMENT ON TABLE public.ventas_comparacion IS
  'Historico de la doble escritura de ventas (Sheet vs Supabase). Se midio del '
  '5 al 16-ago-2026: 12 dias, 65 ventas cotejadas, 0 faltantes. Con esa '
  'evidencia se apago la escritura a la hoja el 17-ago-2026 (v170) y se '
  'desagendo comparar_ventas_diario. La tabla se conserva como prueba; ya no '
  'se alimenta.';


-- ── 3 · Comprobar que quedó como debe ───────────────────────
-- Esto es lo que hay que leer al terminar: `trabajo_nocturno_agendado` tiene
-- que decir FALSE, y los 12 dias medidos tienen que seguir ahí.
SELECT public.estado_comparacion('1217');


-- ============================================================
--  SI HUBIERA QUE VOLVER ATRÁS
-- ============================================================
--
--  Revertir el apagado es revertir el commit de v170 en el tablero: la app
--  vuelve a escribir en los dos lados. Para recuperar también la medición:
--
--    SELECT cron.schedule('comparar_ventas_diario', '0 8 * * *',
--           $sql$ SELECT public.comparar_ventas_guardar('1217'); $sql$);
--
--  Ojo con lo que NO se recupera: los días que la hoja no recibió ventas
--  quedan con un hueco que no se puede rellenar. `listo_para_apagar` los
--  contaría como días sin medir, que es lo correcto.
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================
