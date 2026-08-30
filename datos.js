/* ============================================================
   TABLERO DEL EQUIPO — HES 1217 Angelópolis
   Archivo de estructura. INTENCIONALMENTE VACÍO.

   Este archivo es público: cualquiera puede pedirlo en
   angeljesus8-blip.github.io/tablero-hes1217/datos.js
   Hasta el 1-ago-2026 traía 105 SKUs con stock, los 24 EOL con sus precios
   y las referencias a los comunicados internos que los sustentaban.

   Los datos ahora llegan del Apps Script, que exige token desde que se cerró
   el endpoint, y el tablero los guarda en el celular de quien entró
   (localStorage, clave hes1217_inv_cache, con caducidad de 72 h).

   El código ya sabía trabajar así: aplicarInventario, aplicarEol,
   aplicarPromos y aplicarAvisos agregan lo que no está local, así que partir
   de vacío es un caso normal, no un error.

   NO vuelvas a poner datos aquí. Si el tablero necesita algo nuevo, va por el
   Apps Script.
   ============================================================ */

window.DATOS = {
  actualizado: null,   // lo pone la nube
  promos:      [],     // se manejan en Captura de Series
  eol:         [],     // llega por modo=eol_cloud
  novedades:   [],
  transito:    [],
  agotados:    [],
  inventario:  [],     // llega por modo=inventario / modo=todo
  avisos:      []      // llega por modo=avisos_cloud
};
