-- SOLO LECTURA. Cuenta cuántas filas de la tienda 1217 hay en CADA tabla de esta base,
-- y lista las tiendas registradas. No cambia nada.
SELECT 'tienda' AS tipo, store_id AS tabla, concat(nombre, ' · activo=', coalesce(activo::text, 'null')) AS filas
  FROM public.tiendas
UNION ALL
SELECT 'filas_1217', c.table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from public.%I where store_id = %L',
                                  c.table_name, '1217'), false, true, '')))[1]::text
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
 WHERE c.table_schema = 'public' AND c.column_name = 'store_id'
ORDER BY 1, 2;
