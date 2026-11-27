@AGENTS.md


## Modo orquestador
El hilo principal (Opus) orquesta: planea, decide, diseña docs/specs y revisa resultados.
- NO escribe código él mismo: toda escritura o edición de código va al subagente `codigo`.
- NO lee muchos archivos él mismo: para revisar o buscar en más de 1-2 archivos usa el subagente `lector` y trabaja con su resumen.
- Documentos de diseño (GDD, specs) sí los escribe el orquestador.
- Tareas independientes pueden ir a varios subagentes en paralelo, sin que dos toquen el mismo archivo.
- Al delegar, da al subagente: la spec a seguir, los archivos exactos y el criterio de "listo".
- Al final, el orquestador revisa el resumen de cada subagente y me entrega un resumen único.
