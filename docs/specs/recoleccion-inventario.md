# Recolección e inventario — F0-3

Base: GDD §§2, 3, 6; plan F2. InventoryService es el único escritor de cantidades. ResourceService decide impactos y loot; el cliente muestra herramientas, animaciones, cantidades y recetas confirmadas. Configs futuros bajo `src/shared/config/`. Los valores no definidos en GDD/plan son **decisión de spec**.

## ItemsConfig y RecipesConfig

Cada definición de ítem contiene `Id`, `DisplayName`, `Kind` (Material/Consumable/Tool), `MaxStack`, `Equippable`, `IconKey`; herramientas agregan `ResourceKind`, `Damage`, `Yield`, `HitCooldown`. Definiciones registradas, nunca propiedades enviadas por cliente. Añadir materiales/recetas usa config; una nueva mecánica de ítem necesita implementación y spec.

| ItemId | Tipo | MaxStack | Uso |
|---|---|---:|---|
| `Madera` | Material | 50 | Herramientas, estructuras, combustible, reparación, vendas |
| `Piedra` | Material | 50 | Herramientas, cimiento y fogata |
| `Pila` | Consumable | 5 | Recarga de linterna; no crafteable |
| `Chatarra` | Material | 20 | MarcoPuerta y reparación de marco; material raro |
| `Hacha` | Tool | 1 | Árboles; no durabilidad en MVP |
| `Pico` | Tool | 1 | Rocas; no durabilidad en MVP |
| `Venda` | Consumable | 10 | Cura personal |

`ItemsConfig.InventorySlots=12`. Modelo: vector de 12 slots `{itemId, count}` o vacío, herramientas con count=1. Rellenar primero pilas existentes, luego primer slot libre. No peso ni orden manual, descarte o comercio en MVP. Piezas de objetivo no ocupan estos slots: manos en ObjectiveService.

| RecipeId en RecipesConfig | Ingredientes | Salida |
|---|---|---|
| `Hacha` | 2 Madera + 2 Piedra | 1 Hacha |
| `Pico` | 2 Madera + 2 Piedra | 1 Pico |
| `Venda` | 3 Madera | 1 Venda |

**Decisión de spec:** vendas abstraen fibras de madera, sin añadir recurso fuera del MVP. Crafteo rápido instantáneo, cantidad solicitada entera de 1 a 5 (`RecipesConfig.MaxBatch`). Solo Alive, manos libres y sin otra interacción; disponible en cualquier lugar de la run. Simular consumo y espacio de salida sobre copia, luego commit completo; si falta un ingrediente o capacidad, no consume nada. No se emite ruido de crafteo en MVP; construir sí. Hacha/Pico no dañan jugadores ni la criatura principal; combate con menores queda fuera de estas recetas.

## Nodos y golpe

Prefabs Arbol/Roca en ServerStorage/Prefabs, marcadores de Studio registrados por WorldService. Cada nodo tiene ID, clase, HP y estado Active/Depleted. Hitbox anclada y sin confianza en eventos `Touched` del cliente. Recursos se reinician solo al comenzar run; no regeneran durante ella.

| Propiedad en ResourcesConfig | Árbol | Roca |
|---|---:|---:|
| HP | 50 | 60 |
| Herramienta | Hacha | Pico |
| Daño con herramienta (ItemsConfig) | 10 | 10 |
| Material base por golpe con herramienta (ItemsConfig) | 2 Madera | 2 Piedra |
| Cooldown con herramienta (ItemsConfig) | 0.8 s | 1 s |
| Mano vacía: daño / producción / cooldown (ResourcesConfig) | 5 / 1 Madera / 1.2 s | 5 / 1 Piedra / 1.2 s |

**Decisión de spec:** se permite extracción lenta a mano para evitar bloqueo tras perder herramientas; herramienta incorrecta se rechaza. El servidor deriva herramienta equipada y modo, no los recibe en `HitResource`. Cooldown con la tolerancia de jitter sin acumulación de [remotes](remotes.md) (F0-4). Alcance máximo 10 studs (plan), desde posición validada hasta punto más cercano de hitbox; raycast LOS hacia ese punto sin atravesar paredes, nodo vivo y run actual, Alive y manos libres. No se aplica daño ni se genera ruido de impacto si se rechaza.

Material se entrega por golpe aceptado, incluido el último; no bonus final. Escalado de producción viene del roster fijado y NightsConfig. Para no perder decimales, acumular residuo por jugador/material: `bruto = base * multiplicador + residuo`, entrega parte entera y conserva fracción. Residuo vive solo en run y se borra al morir; se confirma junto al golpe. Si no caben todos los ítems enteros de ese golpe, rechazar sin dañar ni consumir cooldown de gameplay; sí consume límite de red. Al llegar a HP 0, nodo se desactiva una vez; dos impactos simultáneos no producen dos recompensas finales.

`ResourceService` aplica ruido de 50 studs mediante StimulusService. Animación cliente puede empezar antes, pero caída del nodo y cambios de inventario esperan al servidor.

## Pilas, chatarra y contenedores

`ResourcesConfig.ZoneLoot`: por cada una de las cuatro zonas, 3 Pila y 6 Chatarra por run, distribuidas en 3 contenedores marcados (1 Pila + 2 Chatarra cada uno). En la base hay 2 Pila compartidas. No escalan con roster inicialmente, no respawnean en run. La cantidad de marcadores debe coincidir o impedir arranque. La aleatoriedad de piezas no mueve ni regenera este loot.

Contenedor cerrado: `SearchContainer` mantenido 1.5 s (`InteractionConfig`), distancia 8 studs y LOS. Abre para todos, no entrega aún material; gasolinera emite 30 studs de ruido al abrir. `PickupLoot` transfiere un lote visible (Pila o Chatarra) completo, hold 0.25 s. Si no cabe, queda en mundo; repetir apertura no crea nuevos lotes. `OpenDoor`/`CloseDoor` en puertas metálicas y búsquedas usan el mismo ruido aprobado. **F0-4:** los lotes de un contenedor no existen en `Workspace` hasta que `SearchContainer` se completa; se crean en ese commit, así el contenido de un contenedor cerrado no replica a ningún cliente. No se acepta una cantidad arbitraria de loot del cliente.

Mochila: contenedor distinto creado por muerte/desconexión, con todas las pilas del inventario. `LootBackpack`, hold 1 s: transfiere en orden estable lo que cabe, completando stacks, y deja resto visible; esta transferencia parcial es deliberada y atómica en ambos inventarios. Se destruye solo vacía o al terminar run. Nunca se incluye pieza de objetivo en mochila. Cada contenedor/loot/mochila admite una reserva a la vez, gestionada por InteractionService.

## Contrato interno y consistencia

`CanApplyDelta(userId, delta)`, `TryApplyDelta(userId, delta, reason)`, `GetSnapshot(userId)` y transferencias entre contenedores operan sobre IDs registrados. Delta solo se construye en servidor; cantidades son enteras no negativas tras el commit. Toda operación produce revisión y motivo auditable. Reservar acciones no descuenta materiales; al finalizar se revalidan y consumen junto a su efecto. Si una clonación validada falla, se revierte consumo y no se publica éxito.

No llamar DataStore por ítem. Cliente recibe únicamente su inventario; no puede consultar el de otros. La vista de mochila muestra cantidades públicas remanentes vía estado del mundo. Repetir un `requestId` no repite un craft/impacto (ver remotes).

## Pruebas futuras en Studio

Dos clientes golpean el mismo último HP; producción total y estado deben ser únicos. Probar mano vacía, herramienta equivocada, alcance 10/10.1, pared interpuesta, spam, inventario lleno, batch decimal/negativo, receta desconocida, craft usando huecos liberados por ingredientes, residuos de escalado 1.2/1.5, saqueo simultáneo y mochila parcial. Morir y volver al amanecer no restaura inventario guardado ni kit inicial.
