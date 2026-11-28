# Plan de trabajo: juego de terror y supervivencia (Roblox)

Base: `Plan de Desarrollo_ Juego de Terror y Supervivencia Roblox.pdf` (visión, arquitectura, 4 sistemas, persistencia).
Este documento agrega: decisiones pendientes, reparto de modelos, flujo de trabajo, stack, estructura del repo y fases con tareas.

---

## 0. Decisiones a cerrar antes de la Fase 1

| # | Decisión | Opciones | Recomendación |
|---|----------|----------|---------------|
| D1 | Modo de juego | A) Co-op 1-4 jugadores por servidor, partida por "run" · B) Mundo persistente por jugador | **A**. Es lo natural en Roblox y simplifica mucho el guardado. |
| D2 | Qué se guarda (DataStore) | A) Solo progreso meta (estadísticas, desbloqueos) · B) Base completa (como en el PDF) | Con D1=A, **A**. Si eligen B, se usa el esquema JSON del PDF. |
| D3 | Objetivo principal (el "con objetivos") | Ver propuesta abajo | Propuesta "Señal de rescate" |
| D4 | Nombre / codename | — | Definir antes de crear el place en Roblox |

**Propuesta D3 – "Señal de rescate":**
- Meta de la partida: reparar una radio/antena para pedir rescate.
- Requiere 4-5 piezas repartidas en zonas del mapa, cada una más lejos y más peligrosa.
- Cada noche es más difícil (más enemigos, niebla más densa, ataques más largos).
- Victoria: radio reparada y sobrevivir la noche final hasta que llega el rescate.
- Derrota: todos los jugadores muertos (o fogata principal destruida, a definir).
- Objetivos secundarios diarios (opcional en MVP): "consigue 10 de madera", "repara 3 paredes", etc.

> El diseño final de D3 lo hace **Opus 5.5** (tarea F0-2).

### Cambios de plan (Mario, 2026-11-27)

- **No hay Fable.** Sus tareas pasan a Opus 5.5.
- **Revisiones de seguridad al final, en una sola pasada.** Las revisiones anti-exploit por fase (F2-5, F3-5 y similares) se quitan de sus fases y se juntan en F7-1. Cada tarea sigue validando en servidor según `AGENTS.md` y `remotes.md`; lo que se mueve es la revisión dedicada.
- **Primero funcional, luego bonito.** UI y arte se hacen funcionales y greybox mientras se construye el juego; el pulido visual (UI final, modelos, animaciones, iluminación fina) queda para la pasada final F7.

---

## 1. Reparto de modelos

| Tipo de trabajo | Modelo | Herramienta | Ejemplos en este proyecto |
|-----------------|--------|-------------|---------------------------|
| Planear, diseñar, arquitectura | **Astra** | Codex | Specs técnicas por sistema, partir fases en tareas, contratos de Remotes, revisar estructura |
| Razonamiento abstracto | **Opus 5.5** | Claude Code | Diseño de terror (ritmo, tensión), objetivos y progresión, balance de dificultad por noche |
| Razonamiento más difícil | **Opus 5.5** (antes Fable) | Claude Code | Anti-exploit y validación en servidor, máquina de estados de la IA + rendimiento de Pathfinding, guardado sin pérdida de datos (session locking), bugs raros de replicación |
| Escribir código | **GPT Sol** | Codex | Sistemas de servidor: Inventory, Building, AI, DayNight, Data |
| Escribir código | **Sonnet** | Claude Code | Cliente y UI: cámara, linterna, preview de construcción, HUD, audio |

**Regla de carriles:** GPT Sol trabaja en `src/server` y Sonnet en `src/client` + `src/ui`. `src/shared` se toca en una sola tarea a la vez. Así pueden ir en paralelo sin chocar.

---

## 2. Flujo por tarea

1. **Spec** – Astra (u Opus 5.5 si es diseño de juego) escribe la spec en `docs/specs/<sistema>.md`.
2. **Código** – GPT Sol o Sonnet implementan la spec. Solo modifican archivos.
3. **Revisión** – Opus 5.5 revisa el resultado de cada tarea (funciona y cumple la spec). La revisión de seguridad dedicada se hace una sola vez al final (F7-1).
4. **Prueba** – Mario prueba en Studio (Play y "Clients and Servers" con 2 jugadores).
5. **Git** – Mario hace rama, commit, push y PR.

Antes de cada prompt nuevo: `git checkout main && git pull`, luego crear la rama de la tarea.

Ningún agente crea ramas, hace commit ni push. Ver `AGENTS.md`.

---

## 3. Stack

| Herramienta | Para qué |
|-------------|----------|
| Roblox Studio | Mapa, modelos, iluminación, pruebas |
| Rojo 7.6.x (vía Rokit) | Sincroniza el código de la carpeta con Studio |
| Rokit | Instala y fija versiones de Rojo, Wally, StyLua, Selene |
| Wally | Paquetes de la comunidad (si hacen falta) |
| StyLua + Selene | Formato y lint de Luau |
| Luau LSP (VS Code) | Autocompletado y tipos |
| Luau `--!strict` | En todos los scripts nuevos |

**Qué vive dónde:**
- **Código** → en el repo (`src/`), sincronizado con Rojo. Nunca editar scripts directamente en Studio.
- **Mapa, modelos, iluminación** → en el place de Studio (guardado en la nube de Roblox). Rojo solo gestiona las carpetas de scripts.
- **Prefabs que el código clona** (Pared, Cimiento, Fogata, enemigo) → en `ServerStorage/Prefabs` dentro de Studio; el código los busca por nombre.

---

## 4. Estructura del repo

```
/
├─ AGENTS.md                 reglas para Codex
├─ CLAUDE.md                 reglas para Claude Code (importa AGENTS.md)
├─ default.project.json      mapeo Rojo
├─ rokit.toml                versiones de herramientas
├─ selene.toml / stylua.toml
├─ docs/
│  ├─ PLAN_DE_TRABAJO.md
│  ├─ GDD.md                 diseño del juego (Opus 5.5)
│  └─ specs/                 una spec por sistema (Astra / Opus 5.5)
└─ src/
   ├─ server/                → ServerScriptService
   │  ├─ init.server.luau    arranque de servicios
   │  └─ services/           InventoryService, BuildingService, AIService, DayNightService, DataService, ObjectiveService
   ├─ client/                → StarterPlayerScripts
   │  ├─ init.client.luau
   │  └─ controllers/        CameraController, HeldItemController, FlashlightController, BuildPreviewController, SoundController
   ├─ ui/                    → StarterGui (HUD, inventario, crafteo)
   └─ shared/                → ReplicatedStorage/Shared
      ├─ config/             ItemsConfig, RecipesConfig, StructuresConfig, EnemiesConfig, NightsConfig
      ├─ Remotes.luau        creación y nombres de todos los Remotes
      └─ types.luau
```

---

## 5. Fases

Duración estimada: 4 semanas (el PDF tenía 3; se agregan setup y la fase de objetivos).
Cada tarea indica modelo y criterio de "listo".

### Fase 0 – Setup y diseño (Días 0-1)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F0-1 | Mario: instalar Rokit, Rojo, plugin de Rojo, crear place Baseplate, activar API Services | Mario | Studio conecta con `rojo serve` |
| F0-2 | GDD: cerrar D1-D3, loop de una partida, objetivos, curva de dificultad por noche, qué asusta y cuándo | Opus 5.5 | `docs/GDD.md` existe y Mario lo aprueba |
| F0-3 | Specs técnicas de los 4 sistemas + ObjectiveService, contratos de Remotes (nombre, dirección, payload, validación) | Astra | `docs/specs/*.md` y tabla de Remotes completa |
| F0-4 | Revisión de seguridad de los contratos de Remotes | Fable | Lista de validaciones y límites de frecuencia por Remote |
| F0-5 | Scaffold: `default.project.json`, carpetas, `Remotes.luau`, configs vacíos, arranque de servidor/cliente | GPT Sol | Studio muestra la estructura y corre sin errores |

### Fase 1 – Greybox y atmósfera (Días 1-3)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F1-1 | Mapa greybox en Studio (bosque con bloques, zona inicial, 4-5 zonas de piezas) | Mario | Mapa recorrible |
| F1-2 | Cámara primera persona + viewbobbing (V alterna a tercera persona, ver F2-6) | Sonnet | Balanceo según velocidad; V cambia de cámara |
| F1-3 | Estamina (regen tras 1.5 s) y salud | Sonnet (cliente) + GPT Sol (validación servidor) | Correr gasta, se regenera, el servidor no acepta velocidades imposibles |
| F1-4 | Linterna con batería | Sonnet | Se gasta, se apaga, HUD muestra batería |
| F1-5 | Lighting Future, Atmosphere, ColorCorrection con presets día/noche | Sonnet | Cambio día/noche visible con un comando de prueba |

### Fase 2 – Recolección e inventario (Días 4-6)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F2-1 | `ItemsConfig` y `RecipesConfig` data-driven | GPT Sol | Agregar un ítem = editar solo config |
| F2-2 | InventoryService (servidor dueño del inventario) | GPT Sol | Inventario en memoria + replicado al cliente |
| F2-3 | Golpe a árbol/roca: herramienta correcta, distancia ≤ 10 studs, HP del recurso | GPT Sol | Recurso cae y suma material solo si pasa validación |
| F2-4 | UI de inventario y crafteo rápido | Sonnet | Se ve el inventario y se craftea una herramienta |
| ~~F2-5~~ | Movida a F7-1 (revisión de seguridad única) | — | — |
| F2-6 | Cámara V (primera/tercera persona), herramienta visible en mano para todos y golpe mínimo (greybox) | Claude Code (`codigo`) | Ambas cámaras funcionan, la herramienta se ve en las dos y para otros jugadores, la tercera no atraviesa paredes |

### Fase 3 – Construcción (Días 7-11)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F3-1 | Prefabs en Studio: Cimiento 8x1x8, Pared 8x8x1, Marco con puerta, Fogata (con Attachments) | Mario | Están en `ServerStorage/Prefabs` |
| F3-2 | BuildPreviewController: raycast 15 studs, snapping a 8 studs y a Attachments, fantasma verde/rojo | Sonnet | El fantasma encaja y cambia de color bien |
| F3-3 | BuildingService: valida materiales, distancia y `GetPartsInPart`, descuenta, clona, asigna `Health` | GPT Sol | Solo se construye lo válido |
| F3-4 | Reparar estructuras y barras de HP | GPT Sol + Sonnet | Reparar gasta materiales y sube HP |
| ~~F3-5~~ | Movida a F7-1 (revisión de seguridad única) | — | — |

### Fase 4 – Día/noche e IA (Días 12-16)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F4-1 | Diseño de la criatura y su comportamiento de terror (qué hace, sonidos, cómo avisa) | Opus 5.5 | Ficha de la criatura en `docs/specs/enemigo.md` |
| F4-2 | Spec de la máquina de estados (Patrullar, Investigar, Acechar, Atacar) + presupuesto de Pathfinding | Opus 5.5 | Spec con transiciones, umbrales y límites de rendimiento |
| F4-3 | DayNightService: reloj global, fases, eventos para cliente | GPT Sol | Todos los jugadores ven la misma hora |
| F4-4 | AIService según F4-2 | GPT Sol | Patrulla, investiga ruido/luz, rodea base, rompe paredes |
| F4-5 | Eventos de ruido/luz (talar, correr, fogata, linterna) | GPT Sol + Sonnet | La IA reacciona a cada estímulo |
| F4-6 | Revisión de rendimiento con varios enemigos | Opus 5.5 | Sin caídas fuertes con 4 jugadores y la cantidad máxima de enemigos |

### Fase 5 – Objetivos y condición de victoria (Días 17-19)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F5-1 | `NightsConfig`: dificultad por noche | Opus 5.5 (valores) + GPT Sol (código) | Cada noche sube la dificultad según GDD |
| F5-2 | ObjectiveService: piezas de radio, progreso compartido, victoria/derrota | GPT Sol | Se puede ganar y perder una partida completa |
| F5-3 | UI de objetivos y pantallas de fin de partida | Sonnet | El jugador siempre sabe qué hacer después |

### Fase 6 – Persistencia, audio y playtest (Días 20-24)

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F6-1 | Spec de guardado (según D2) con session locking y reintentos | Opus 5.5 | Spec aprobada |
| F6-2 | DataService | GPT Sol | Guarda y carga sin perder datos al salir/entrar rápido |
| F6-3 | Audio 3D: pasos, ramas, golpes en madera, criatura, ambiente | Sonnet | Sonidos espaciales correctos |
| F6-4 | Playtest con 2-4 personas + lista de bugs y balance | Mario + Opus 5.5 (análisis de feedback) | Lista priorizada para la siguiente iteración |

### Fase 7 – Pasada final: seguridad, UI y arte

Se hace con el juego ya completo y funcional (cambios de plan del 2026-11-27).

| ID | Tarea | Modelo | Listo cuando |
|----|-------|--------|--------------|
| F7-1 | Revisión de seguridad única de todos los Remotes y sistemas de servidor (incluye las antiguas F2-5 y F3-5: spam de Remote y distancia falsa no dan materiales; no se puede construir gratis, lejos ni encimado; IA, objetivos y guardado) | Opus 5.5 | Lista de hallazgos corregida; pruebas de exploit en Studio sin éxito |
| F7-2 | UI final: HUD, inventario, crafteo, objetivos y pantallas de fin | Sonnet / `codigo` | UI coherente y legible en PC y móvil |
| F7-3 | Arte: modelos de herramientas y linterna, prefabs, animaciones de personaje (golpe, sostener), iluminación fina | Mario + `codigo` | Sustituye el greybox sin cambiar contratos (nombres, `Handle`, `Grip`, `Hitbox`) |
| F7-4 | Playtest final tras la pasada | Mario + Opus 5.5 | Sin regresiones respecto a F6-4 |

---

## 6. Primeros pasos (hoy)

1. Cerrar D1-D4 (o aceptar las recomendaciones).
2. F0-1: instalar herramientas (Mario).
3. F0-2: GDD con Opus 5.5.
4. F0-3: specs con Astra.
5. F0-5: scaffold con GPT Sol.
