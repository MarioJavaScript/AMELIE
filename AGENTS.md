# Reglas para agentes (Codex y Claude Code)

## Proyecto
Juego de terror y supervivencia en primera persona para Roblox, co-op.
Plan: `docs/PLAN_DE_TRABAJO.md` · Diseño: `docs/GDD.md` · Specs: `docs/specs/`.
Lee la spec de tu tarea antes de escribir código. Si no existe, detente y dilo.

## Git (obligatorio)
- NO crees ramas, NO hagas commit, NO hagas push. Solo modifica archivos.
- Al terminar, entrega un resumen: archivos tocados, qué cambió, cómo probarlo en Studio.

## Código
- Luau con `--!strict` en todo archivo nuevo.
- El código vive en `src/` y se sincroniza con Rojo. No asumas scripts creados a mano en Studio.
- Prefabs (Pared, Cimiento, Fogata, enemigos) están en `ServerStorage/Prefabs`; búscalos por nombre, no los crees por código.
- El servidor es la autoridad: inventario, construcción, daño, IA y guardado se deciden en el servidor.
- Todo Remote se declara en `src/shared/Remotes.luau`. Cada handler de servidor valida tipos, distancia, materiales y frecuencia. Nunca confíes en datos del cliente.
- Valores de diseño (costos, HP, tiempos, distancias) van en `src/shared/config/`, no hardcodeados.
- Sin emojis en código, UI ni textos.

## Carriles
- `src/server/` → tareas de servidor.
- `src/client/` y `src/ui/` → tareas de cliente.
- `src/shared/` → solo si tu tarea lo indica.
No toques archivos fuera del carril de tu tarea sin decirlo en el resumen.

## Herramientas
- Formato: `stylua src`
- Lint: `selene src`
- Ambos deben pasar antes de entregar.
