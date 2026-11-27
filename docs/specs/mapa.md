# Spec: Mapa greybox (F1-1)

Estado: propuesta para aprobar. Fuente: GDD.md (2.1, 4, 5), objetivos.md, recoleccion-inventario.md, estimulos.md, ciclo-partida.md, arquitectura.md (Workspace/Map, Workspace/Markers), construccion.md, WorldConfig.luau.

Objetivo: un solo mapa greybox, construido por `tools/map/MapBuilder.luau` (determinista e idempotente), con el claro de la base, 4 zonas de piezas, caminos, agua, colina, montaña, mina y todos los marcadores que piden las specs.

## 0. Convenciones

- Ejes: Y arriba. X+ = este, Z- = norte, Z+ = sur (convención de Roblox: el frente por defecto mira a Z-).
- Origen (0, 0, 0) = centro de la caseta de radio. El suelo general está en Y = 0.
- Distancias en studs, medidas en planta (XZ) desde el origen.
- Todas las coordenadas son de diseño greybox; si un ajuste visual lo exige se pueden mover hasta 8 studs sin cambiar esta spec, pero las distancias a la base no deben variar más de un 10 %.
- Paleta greybox: edificios y estructuras en grises (`Medium stone grey`, `Dark stone grey`), madera en `Brown`, vegetación en verdes apagados, marcadores invisibles.

## 1. Tamaño del mapa y base

- Terreno: de -800 a 800 en X y Z (1600 x 1600).
- Área jugable: de -760 a 760 en X y Z. Muros invisibles en `Map/Limites` en los 4 bordes (altura 300). Montañas y bosque denso cierran la vista antes del muro.
- `WorldConfig.MapBounds` (en `src/shared/config/WorldConfig.luau`, excepción aprobada para esta tarea): `{ MinX = -760, MaxX = 760, MinZ = -760, MaxZ = 760, MinY = -20, MaxY = 300 }`. Lo usa el watchdog de piezas (objetivos.md).

### Base (claro)

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Claro | centro (0, 0, 0) | radio 60 sin árboles | Grass plano en Y = 0 |
| Caseta de radio | centro (0, 0, 0) | 16 x 10 x 12 (X -8..8, Z -6..6) | Puerta al sur (Z = 6, X -2..2, 4 de ancho). Ventanas en norte, este y oeste |
| Mesa de la radio | (0, 0, -4) | 6 x 3 x 2 | Pegada a la pared norte |
| Radio | (0, 3.5, -4) | modelo 4 x 2 x 2 | Fija, indestructible, 4 sockets visuales |
| Fogata (socket) | (0, 0, 18) | 4 x 1 x 4 | Único `CampfireSocket` |
| BaseSpawn | (-8, 0, 18) | 8 x 1 x 8 | A 8 studs de la fogata, dentro del radio seguro de noche 1 |
| Estante base | (6, 0, -4) | 2 x 5 x 4 | Lugar del loot de base (2 Pila) |
| BuildZone Base | centro (0, 0, 0) | 96 x 96 (X -48..48, Z -48..48), cota 0 | 12 x 12 celdas de 8 |

Salidas del claro: norte (cortafuegos a la torre), este (sendero a la gasolinera) y suroeste (sendero al pantano). Las ventanas de la caseta miran al norte: desde dentro se ve el cortafuegos y el puente.

## 2. Zonas

Orden de ritmo: gasolinera (cerca, tutorial) -> torre (expuesta, pieza pesada) -> pantano (niebla, agua, acechadores desde noche 3) -> mina (oscuridad, nido).

Un arroyo separa el lado seguro (base, gasolinera, pantano) del lado lejano (torre, mina). Cruzar agua es entrar en peligro.

| Zona (ZoneId) | Dirección | Centro de zona | Distancia | Volumen de zona (centro, tamaño) |
|---|---|---|---|---|
| Base | - | (0, 0, 0) | 0 | (0, 10, 0), 100 x 40 x 100 |
| Gasolinera | este | (150, 0, 0) | 150 | (155, 15, 5), 110 x 40 x 120 |
| Torre | norte | (0, 40, -300) | 300 | (0, 50, -300), 200 x 120 x 200 |
| Pantano | suroeste | (-320, 0, 320) | 452 | (-320, 15, 320), 240 x 40 x 240 |
| Mina | noreste | entrada (400, 0, -440) | 595 (entrada) | (405, 15, -545), 130 x 40 x 250 |

Fuera de cualquier volumen = `Bosque`. Los volúmenes sirven para revelar piezas (objetivos.md) y para el ambiente por zona en el cliente.

### 2.1 Gasolinera (~150, tutorial)

Gasolinera abandonada junto a una carretera cortada por los dos lados.

| Elemento | Posición (centro) | Tamaño | Notas |
|---|---|---|---|
| Carretera | X = 180, Z de -226 a 200 | 16 de ancho | Asphalt pintado en el terreno |
| Corte norte | (180, 0, -234) | puente caído | 2 losas inclinadas hundidas en el arroyo. No se cruza por aquí |
| Corte sur | (180, 0, 205) | derrumbe | Pila de roca de Terrain que corta la carretera |
| Tienda | (140, 0, -10) | 28 x 10 x 18 (X 126..154, Z -19..-1) | Puerta este (X = 154). Almacén al fondo (X 126..134) con tabique y hueco de puerta |
| Taller | (140, 0, 22) | 14 x 10 x 14 (X 133..147, Z 15..29) | Hueco de cierre metálico al este |
| Marquesina | (166, 12, 10) | 24 x 1 x 16 sobre 4 columnas | Surtidores en (166, 0, 6) y (166, 0, 14) |
| Coches | (172, 0, 10), (184, 0, -40), (176, 0, 60), (185, 0, 120) | 6 x 5 x 12 | Siluetas oscuras que a lo lejos parecen figuras |
| Estanterías | dentro de la tienda | 2 x 6 x 8, 3 filas | Cortan la visión dentro |

Las puertas metálicas no están especificadas como interactuables. Por ahora son huecos; las Parts `PuertaMetalica` llegarán con la spec de interacción.

### 2.2 Torre (~300, expuesta)

Torre de vigilancia forestal en lo alto de una colina abierta. Es la referencia del mapa: se ve desde casi todo el mapa.

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Colina | Terrain FillBall centro (0, -160, -300), radio 200 | cima en Y = 40, pie de radio 120 | Grass con afloramientos de Rock. Sin árboles por encima de Y = 20 |
| Torre | patas en las esquinas de 10 x 10 centrado en (0, 40, -300) | de Y 40 a 80 | 4 patas de 1.5 x 40 x 1.5 con riostras |
| Descanso | (0, 60, -300) | 8 x 1 x 8 | A media altura. Barandilla de 3 de alto con un hueco de 4 en el lado norte para soltar la Antena |
| Cabina | (0, 80, -300) | 14 x 8 x 14, suelo con la cara superior en Y = 80 | Barandilla de 3 de alto con un hueco de 4 en el lado norte para soltar la Antena. Techo en Y = 89 |
| Zona de caída | (0, 40, -312) | suelo de la colina | Ahí cae la Antena soltada por los huecos. Sin rocas ni árboles en un radio de 6 |
| Escalera | cara sur, TrussPart | de Y 40 a 60 y de 60 a 80 | Lenta a propósito |
| Caseta de herramientas | (18, 40, -292) | 8 x 7 x 8 | Único escondite de la zona |

Línea de visión clave: desde la cabina se ve el claro de la base por el cortafuegos, el puente, la gasolinera y la boca de la mina. Desde arriba se puede ver venir a la criatura.

### 2.3 Pantano (~450, niebla y agua)

Campamento hundido en un pantano de poca profundidad.

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Cuenca | X -420..-220, Z 220..420 | 200 x 200 | Fondo de Mud en Y = -3; agua hasta Y = -1 (profundidad 2); orillas en Y = 0 |
| Islotes | 6 islotes de Mud y LeafyGrass | radio 8 a 14, cara superior en Y = 1 | Repartidos entre las cabañas |
| Cabaña C1 | (-270, 0, 280) | 12 x 8 x 10 | Inclinada 4 grados. Suelo con la cara superior en Y = 1 |
| Cabaña C2 | (-330, 0, 290) | 12 x 8 x 10 | Inclinada 6 grados |
| Cabaña C3 | (-300, 0, 350) | 12 x 8 x 10 | Inclinada 5 grados |
| Cabaña C4 | (-380, 0, 350) | 12 x 8 x 10 | Inclinada 8 grados. Sin pasarela: solo se llega vadeando |
| Pasarelas | (-236, 236) -> (-260, 264) -> C1 -> (-300, 284) -> C2 -> (-310, 320) -> C3 | 4 de ancho, cara superior en Y = 1 | En fila india: cuello de botella |
| Bote volcado | (-350, 0, 260) | 4 x 2 x 10 | En el agua |
| Árboles muertos | 30 en islotes y orillas | tronco sin copa | Decorado |

Para llegar a C4 hay que vadear 30 studs desde C2 o C3; cada paso en el agua hace ruido (`WaterStep` 25).

### 2.4 Mina (~600, oscuridad y nido)

Mina al pie de la montaña. El interior se excava en la roca de Terrain (FillBlock con Air) y se refuerza con Parts.

Montaña de la mina: Terrain FillBall de Rock con centro (400, -127, -797) y radio 377. Cima en Y = 250; el pie queda en Z = -442 frente a la entrada.

| Espacio excavado | Centro | Tamaño (X x Y x Z) | Notas |
|---|---|---|---|
| Túnel A (entrada) | (400, 6, -462) | 12 x 12 x 75 (Z -425..-500) | Marcos de madera cada 12 studs. Nicho lateral en (406, 0, -470) |
| Galería | (400, 7, -520) | 40 x 14 x 30 | Bifurcación. Vagoneta y rieles |
| Túnel B1 | (360, 5, -520) | 40 x 10 x 10 | Hacia el oeste |
| Túnel B2 | (340, 5, -555) | 10 x 10 x 60 | Hacia el norte |
| Pozo | (340, 10, -600) | 30 x 20 x 30 | Pozo vertical derrumbado de 8 x 30 x 8 hacia arriba, sin salida |
| Túnel C | (400, 6, -577) | 12 x 12 x 84 | De la galería al nido |
| Nido | (420, 9, -640) | 50 x 18 x 40 (X 395..445, Z -620..-660) | Cámara más profunda |
| Gatera 1 | (367.5, 4, -600) | 25 x 8 x 6 | Del pozo hacia el este |
| Gatera 2 | (380, 4, -620) | 6 x 8 x 40 | Hacia el sur |
| Gatera 3 | (387.5, 4, -640) | 15 x 8 x 6 | Entra al nido por el oeste |

El circuito galería -> pozo -> gatera -> nido -> túnel C -> galería forma un bucle: hay ruta de escape, pero pasa por el nido.

Sin ninguna fuente de luz dentro. La oscuridad total depende de Lighting (ambient interior), que no se toca en esta tarea.

## 3. Puntos de aparición de piezas

Ruta: `Workspace/Markers/ObjectiveSpawns/<PieceId>/01..03`. Parte de 2 x 1 x 2 con la cara inferior apoyada en el suelo indicado.

| PieceId | 01 | 02 | 03 |
|---|---|---|---|
| Bateria | Almacén de la tienda (130, 0, -14) | Taller (138, 0, 26) | Detrás del coche de la carretera (184, 0, -47) |
| Antena | Cabina de la torre (0, 80, -300) | Descanso (0, 60, -300) | Caseta de herramientas (18, 40, -292) |
| Transceptor | Cabaña C2 (-332, 1, 292) | Cabaña C3 (-302, 1, 352) | Cabaña C4 (-382, 1, 352) |
| Cristal | Galería (412, 0, -528) | Pozo (336, 0, -606) | Nido (440, 0, -652) |

Distancias reales de los spawns a la base: Bateria de 130 a 190, Antena ~300, Transceptor de 410 a 520, Cristal de 660 a 780. Cristal/03 está a 20 studs de donde duerme la criatura.

Decisión (objetivos.md): quien carga la Antena no puede usar escaleras. Desde 01 y 02 se suelta por el hueco de la barandilla, cae al pie de la torre y emite `PieceImpact` (60 studs). Bajar la antena siempre hace ruido.

## 4. Caminos, referencias, visión, cuellos de botella y escondites

### 4.1 Arroyo

Cauce de 10 de ancho con el fondo en Y = -3 y agua hasta Y = -1. Polilínea:

(470, -445) manantial al pie de la montaña -> (300, -330) -> (100, -170) -> (-80, -120) -> (-220, 60) -> (-300, 250), donde desemboca en el pantano.

### 4.2 Caminos

Se pintan con `Terrain:ReplaceMaterial` sobre el terreno ya creado, sin cambiar su forma.

| Id | Recorrido | Ancho | Material | Notas |
|---|---|---|---|---|
| Sendero Gasolinera | (44, 0) -> (120, 0) -> (172, 0) | 8 | Ground | Corto y recto. Tutorial |
| Carretera | (180, -226) -> (180, 200) | 16 | Asphalt | Cortada en los dos extremos |
| Cortafuegos | (0, -48) -> (0, -180) | 20 sin árboles; franja de Ground de 6 en el centro | Ground | Pasillo largo y abierto |
| Subida a la torre | (0, -180) -> (0, -292) | 6 | Ground | Cara sur de la colina |
| Sendero Pantano | (-36, 36) -> (-120, 90) -> (-180, 190) -> (-236, 236) | 6 | Ground | Sinuoso; termina en las pasarelas |
| Cresta | (60, -300) -> (250, -380) -> (400, -440) | 6 | Ground | De la torre a la mina, siempre al norte del arroyo |
| Atajo de la mina | (180, -220) -> (215, -262) -> (260, -340) -> (330, -415) | 6 | Ground | Cruza el arroyo por un tronco y se une a la cresta |

Hay dos rutas a la mina: por la torre (larga y expuesta) o por la carretera y el tronco (más corta, pero con un cruce estrecho).

### 4.3 Referencias visibles de lejos

- La torre (cabina a Y 80-89 sobre una colina de 40) es la referencia principal.
- La montaña de la mina cierra el noreste.
- La marquesina de la gasolinera se ve desde el sendero este.
- La caseta no se ve desde lejos; de noche la referencia de la base es la fogata.

### 4.4 Líneas de visión

- Torre -> base por el cortafuegos (pasillo de 20 sin árboles).
- Ventanas norte de la caseta -> cortafuegos y puente.
- Entrada de la mina -> cresta: quien sale de la mina ve la torre.
- El pantano no tiene líneas largas: niebla, árboles muertos y cabañas.

### 4.5 Cuellos de botella

| Id | Posición | Tamaño | Qué obliga |
|---|---|---|---|
| Puente del cortafuegos | (0, 0, -142), orientado N-S | 6 x 1 x 16, cara superior en Y = 1 | Pasar en fila o vadear (ruido) |
| Tronco del arroyo | (215, 0, -262), perpendicular al cauce | 3 x 3 x 18 | Uno a la vez, lento |
| Pasarelas del pantano | sección 2.3 | 4 de ancho | Fila india sobre el agua |
| Escalera de la torre | sección 2.2 | TrussPart | Lenta, sin cobertura |
| Túnel A de la mina | sección 2.4 | 12 de ancho, 75 de largo | Única entrada |
| Gateras de la mina | sección 2.4 | 6 x 8 | Estrecho, sin vuelta atrás rápida |

### 4.6 Escondites

Ruta: `Workspace/Markers/Hideouts`, tag `Hideout` (adición, ver sección 8).

| Nombre | Posición |
|---|---|
| Gasolinera_Almacen | (130, 0, -14) |
| Gasolinera_Taller | (140, 0, 22) |
| Matorral_Este | (70, 0, -60) |
| Matorral_Oeste | (-80, 0, 60) |
| Matorral_Arroyo | (150, 0, -150) |
| Torre_Caseta | (18, 40, -292) |
| Pantano_C3 | (-300, 1, 350) |
| Mina_Nicho | (406, 0, -470) |

Los matorrales son grupos de 6 bolas de 6 a 8 studs con `CanCollide = false`: tapan la vista y se puede entrar en ellos.

## 5. Enemigos: aparición y patrulla

EnemiesConfig está vacío y enemigo.md no existe. Estos puntos son una propuesta de colocación; su uso lo decide F4-1/F4-2.

### 5.1 Aparición

Ruta: `Workspace/Markers/EnemySpawns`, tag `EnemySpawn`, atributo `EnemyKind`.

| Nombre | EnemyKind | Posición |
|---|---|---|
| CriaturaPrincipal_01 | CriaturaPrincipal | (420, 0, -645), en el nido |
| AcechadorMenor_01 | AcechadorMenor | (-400, -3, 380), agua honda del pantano |
| AcechadorMenor_02 | AcechadorMenor | (-260, -3, 390) |
| AcechadorMenor_03 | AcechadorMenor | (-390, -3, 250) |

Volumen `Workspace/Markers/Nest`: centro (420, 9, -640), 50 x 18 x 40, coincide con la cámara del nido.

### 5.2 Patrulla

Ruta: `Workspace/Markers/PatrolPoints/<RouteId>/NN` (adición). Tag `PatrolPoint`, atributos `RouteId` y `Order`. La Y se toma de la superficie con un raycast.

| RouteId | Para | Puntos en orden (X, Z) |
|---|---|---|
| Bosque | Criatura de noche, rodea la base | (0, -125), (110, -90), (120, 70), (40, 140), (-90, 130), (-150, 10), (-110, -100) |
| Exterior | Criatura, recorrido largo entre zonas | (0, -200), (60, -300), (215, -262), (190, 100), (-200, 200), (-200, -60), (-60, -150) |
| Mina | Criatura dentro de la mina | (400, -450), (400, -520), (340, -600), (380, -620), (420, -640) |
| Pantano | Acechadores | (-260, 260), (-250, 340), (-320, 400), (-400, 360), (-400, 280), (-330, 240) |

## 6. Árboles y rocas recolectables

Según recoleccion-inventario.md y arquitectura.md, los árboles y rocas recolectables son clones de los prefabs `Arbol` y `Roca` de `ServerStorage/Prefabs`. Los crea el servidor en cada run sobre los marcadores `ResourceSpawns` y no regeneran durante la run. El mapa solo pone los marcadores.

Los prefabs greybox `Arbol` y `Roca` los crea en Studio `tools/map/PrefabBuilder.luau` (decisión aprobada). Es idempotente: reemplaza solo `ServerStorage/Prefabs/Arbol` y `ServerStorage/Prefabs/Roca` y no toca otros prefabs. La estructura y los atributos siguen recoleccion-inventario.md y arquitectura.md: Model con PrimaryPart en la base como pivote, sin Scripts. La regla de no crear prefabs por código aplica al juego en runtime, no al contenido construido en Studio.

Ruta: `Workspace/Markers/ResourceSpawns/<Kind>_NNN` (por ejemplo `Arbol_001`, `Roca_001`). Tag `ResourceSpawn`, atributos `Kind` ("Arbol" o "Roca") y `ZoneId`.

| Zona | Arbol | Roca | Dónde |
|---|---|---|---|
| Base | 16 | 6 | Anillo de radio 56 a 96, fuera de la BuildZone |
| Bosque | 36 | 10 | A 8-20 studs de los senderos, fuera de los volúmenes de zona |
| Gasolinera | 4 | 6 | Rocas en el derrumbe sur |
| Torre | 4 | 8 | Árboles al pie de la colina; rocas en los afloramientos |
| Pantano | 8 | 2 | Islotes y orillas |
| Mina | 0 | 10 | 4 fuera de la entrada y 6 en la galería y el pozo (codicia contra ruido: `ResourceHit` 50 junto al nido) |
| Total | 68 | 42 | 110 nodos |

Reglas de colocación (deterministas, con semilla fija):
- Separación mínima de 8 entre nodos.
- Ninguno a menos de 6 del centro de un camino, sobre el agua, en una NoBuildZone ni a menos de 4 de un marcador de pieza, loot o spawn.
- La Y sale de un raycast contra el terreno y las Parts del mapa.

### Bosque decorativo (no recolectable)

En `Map/Bosque`. Su función es cerrar la vista y dar escondites.

- Rejilla de 18 studs con desplazamiento aleatorio de hasta 6, con semilla fija.
- Probabilidad de 0.55 a menos de 150 studs de un camino o zona, y 0.15 más lejos. Tope de 2500 árboles.
- Exclusiones:
  - claro de la base (radio 60);
  - cortafuegos (|X| < 12, Z -180..-48);
  - a menos de 10 del centro de un camino;
  - agua más 4 studs;
  - volúmenes de zona (excepto los árboles muertos del pantano);
  - colina por encima de Y = 20 y montañas.
- Forma: tronco cilíndrico de 2.5 x 24 (colisiona) y copa de 10 x 14 x 10 (`CanCollide = false`). Más alto y oscuro que el prefab `Arbol`, para no confundirlos.

## 7. Terrain y Parts

| Con Terrain | Con Parts |
|---|---|
| Suelo general (Grass, cara superior en Y = 0) | Caseta, mesa, radio y estante |
| Colina de la torre (FillBall, Grass y Rock) | Torre, descanso, cabina, escalera (TrussPart) y caseta de herramientas |
| Montaña de la mina y cordilleras de borde (FillBall de Rock y Slate) | Tienda, taller, marquesina, surtidores, coches y estanterías |
| Interior de la mina (FillBlock con Air) | Marcos y soportes de la mina, vagoneta y rieles |
| Arroyo y pantano (Mud y Water) | Cabañas, pasarelas, bote, puente y tronco |
| Islotes (Mud y LeafyGrass) | Puente caído de la carretera |
| Derrumbe sur de la carretera (Rock) | Bosque decorativo, matorrales y árboles muertos |
| Caminos y carretera (ReplaceMaterial con Ground y Asphalt) | Muros límite invisibles, volúmenes de zona y todos los marcadores |

Cordilleras de borde (FillBall de Rock):
- norte (0, -300, -950), radio 400;
- este (950, -300, 0), radio 400;
- sur (0, -300, 950), radio 400;
- oeste (-950, -300, 0), radio 400;
- esquinas (-720, -250, -720), (720, -250, 720) y (-720, -250, 720), radio 380.

La esquina noreste la cierra la montaña de la mina.

## 8. Jerarquía, nombres y tags

La jerarquía de carpetas sigue arquitectura.md y es la fuente de verdad. Los tags de CollectionService son una adición de esta spec (ninguna spec ni código los usa todavía): duplican los marcadores para que se puedan consultar con `GetTagged`.

```
Workspace
  Map                         (Folder; lo reconstruye MapBuilder)
    Zones                     (Folder) Base, Gasolinera, Torre, Pantano, Mina   tag MapZone, attr ZoneId
    Base                      (Folder) Caseta (Model), Radio (Model), Estante
    Gasolinera                (Folder) Tienda, Taller, Marquesina, Coches, PuenteCaido
    Torre                     (Folder) Torre (Model), CasetaHerramientas
    Pantano                   (Folder) Cabanas (C1..C4), Pasarelas, Bote, ArbolesMuertos
    Mina                      (Folder) Soportes, Vagoneta, Rieles, Portal
    Caminos                   (Folder) PuenteCortafuegos, TroncoArroyo
    Bosque                    (Folder) Arboles, Matorrales
    Limites                   (Folder) Muro_N, Muro_S, Muro_E, Muro_O
  Markers                     (Folder; lo reconstruye MapBuilder)
    BaseSpawn                 (Part)
    RadioSocket               (Part)
    CampfireSocket            (Part)
    ObjectiveSpawns/<PieceId>/01..03   tag PieceSpawn, attr PieceId, ZoneId
    ResourceSpawns/<Kind>_NNN          tag ResourceSpawn, attr Kind, ZoneId
    LootSpawns/<ZoneId>_NN             tag LootSpawn, attr ZoneId
    EnemySpawns/<EnemyKind>_NN         tag EnemySpawn, attr EnemyKind
    Nest                      (Part, volumen)  tag Nest
    WaterZones/<Id>           (Parts, volumen) tag WaterZone
    BuildZones/Base           (Part, volumen)  tag BuildZone
    NoBuildZones/<Id>         (Parts, volumen) tag NoBuildZone
    PatrolPoints/<RouteId>/NN  (adición)       tag PatrolPoint, attr RouteId, Order
    Hideouts/<Nombre>          (adición)       tag Hideout, attr ZoneId
  Runtime                     (no lo toca MapBuilder)
```

### Radio

`Map/Base/Radio` es un Model con el atributo `InteractableId = "radio"` y 4 Parts `Socket_Bateria`, `Socket_Antena`, `Socket_Transceptor` y `Socket_Cristal`, que corresponden a los huecos `radio:<PieceId>` de objetivos.md.

### LootSpawns

13 en total, según recoleccion-inventario.md:
- 3 por zona de pieza (`<ZoneId>_01..03`): un contenedor con 1 Pila y 2 Chatarra cada uno;
- `Base_01` en el estante de la caseta.

| ZoneId | 01 | 02 | 03 |
|---|---|---|---|
| Gasolinera | Mostrador (146, 0, -6) | Banco del taller (134, 0, 18) | Coche de los surtidores (172, 0, 4) |
| Torre | Cabina (4, 80, -304) | Caseta de herramientas (20, 40, -290) | Pie de la torre (-6, 40, -296) |
| Pantano | C1 (-272, 1, 282) | C3 (-298, 1, 348) | Bote (-350, 0, 260) |
| Mina | Nicho del túnel (406, 0, -470) | Galería (388, 0, -512) | Pozo (348, 0, -592) |

### WaterZones

Volúmenes de Y -3.5 a 0.5. Con los pies en una pasarela o en el suelo de una cabaña (Y = 1) se está fuera; vadeando se está dentro.
- `Pantano`: X -420..-220, Z 220..420.
- `Arroyo_1` a `Arroyo_5`: cajas rotadas, una por tramo de la polilínea, de 12 de ancho.

### NoBuildZones

Incluyen el margen de 4 de `WorldConfig.ProtectedRadiusStuds`.

| Id | Centro | Tamaño |
|---|---|---|
| Caseta | (0, 5, 0) | 24 x 12 x 20 |
| PuertaCaseta | (0, 5, 12) | 8 x 12 x 12 |
| Fogata | (0, 5, 18) | 12 x 12 x 12 |
| BaseSpawn | (-8, 5, 18) | 16 x 12 x 16 |

Las salidas del claro no son NoBuild: se pueden fortificar con `MarcoPuerta`.

### Propiedades comunes de marcadores y volúmenes

- `Anchored = true`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`, `Transparency = 1`.
- Los servicios leen su posición y tamaño por matemática (punto dentro de caja) o por consultas propias, no por `Touched` (estimulos.md). Con `CanQuery = false`, los raycasts de línea de visión y los del PlayerService no los golpean.
- Todo lo que está dentro de una zona lleva el atributo `ZoneId`.

## 9. Notas de terror

- **Base:** es segura pero ciega. Solo las ventanas norte dan visión; el sur es bosque cerrado a 60 studs.
- **Cortafuegos:** 130 studs de pasillo abierto. De noche se ve a la criatura cruzar el puente antes de que llegue. Es tensión anunciada.
- **Arroyo:** su murmullo constante tapa pasos lejanos. Cruzar por el puente o el tronco obliga a ir en fila; vadear hace ruido. Ahí se decide entre ir despacio o hacer ruido.
- **Gasolinera:** zona de aprendizaje. Las puertas metálicas y los contenedores (`MetalOpen` 30) enseñan que el ruido atrae. Los coches oscuros a lo lejos parecen figuras.
- **Torre:** desnuda, sin donde esconderse. La escalera es lenta y la Antena pesada obliga a volver a velocidad 8. Conviene hacerla de día. Desde arriba se ve todo, y también te ven.
- **Pantano:** niebla espesa incluso de día (Atmosphere por zona en el cliente, fuera de esta tarea), agua ruidosa y pasarelas en fila. Las ranas callan cuando hay acechadores cerca ("presencia: el ambiente se apaga", GDD). C4 obliga a meterse al agua.
- **Mina:** oscuridad total, 75 studs de túnel sin salida lateral y la bifurcación en la galería. El bucle de las gateras es la única escapatoria. De día la criatura duerme en el nido, a 20 studs de Cristal/03. Las rocas de la mina tientan a picar (50 de ruido).
- **Sonido:** posiciones para audio futuro:
  - murmullo a lo largo del arroyo;
  - viento en la cima de la torre;
  - goteo en la galería y el pozo;
  - ranas en el pantano;
  - metal crujiendo en la marquesina.

  Sin marcadores de audio en esta tarea.
- **Oscuridad:** la mina y el interior de las cabañas no tienen luz. La niebla, el Ambient y la tecnología Future se ajustan en Lighting y en el EnvironmentController, que quedan fuera de esta tarea.

## 10. MapBuilder (tools/map/MapBuilder.luau)

- `--!strict`. Se ejecuta en Studio con `execute_luau`, en modo Edit, nunca en Play.
- Idempotente: al empezar, `Workspace.Terrain:Clear()` y destruye `Workspace.Map` y `Workspace.Markers` si existen. No toca `Workspace.Runtime`, Lighting ni ServerStorage.
- Determinista: `Random.new(20261127)` para todo lo aleatorio. Cada sección usa su propio `Random` derivado, para que ejecutar una sección suelta dé el mismo resultado.
- Secciones ejecutables por separado (variable `SECTION` al inicio, o `"All"`):
  - `Terreno`: suelo, montañas, colina, arroyo, pantano y excavación de la mina;
  - `Caminos`;
  - `Base`;
  - `Gasolinera`;
  - `Torre`;
  - `Pantano`;
  - `Mina`;
  - `Bosque`;
  - `Marcadores`.

  Las secciones que dependen del terreno (raycast) van después de `Terreno`. Si la sección es `"All"` o `Terreno`, limpia todo; si no, limpia solo su propia carpeta.
- El terreno se rellena en bloques de 200 x 200 para no bloquear Studio.
- Todos los nombres, carpetas, tags y atributos, exactamente como en la sección 8.

### Criterio de listo

La verificación se hace con `search_game_tree` y por código.
- 4 `MapZone` más Base; 12 `PieceSpawn` (3 por `PieceId`); 110 `ResourceSpawn` (68 Arbol y 42 Roca); 13 `LootSpawn`; 4 `EnemySpawn`; 1 `Nest`; 6 `WaterZone`; 1 `BuildZone`; 4 `NoBuildZone`; 25 `PatrolPoint` en 4 rutas; 8 `Hideout`.
- Existen `BaseSpawn`, `RadioSocket`, `CampfireSocket` y `Map/Base/Radio` con sus 4 sockets.
- Ningún marcador queda a más de 2 studs por encima o por debajo de su superficie.
- Distancias de las zonas a la base dentro del 10 % de la sección 2.
- Capturas de la base, cada zona y la vista desde la torre sin huecos de terreno ni Parts flotando.

## Pendientes y fuera de esta spec

- Pendiente, tarea de Lighting aparte: niebla espesa del pantano incluso de día, oscuridad total en la mina y dentro de las cabañas (Ambient y OutdoorAmbient por zona), Atmosphere por zona.
- Pendiente de config: `StimuliConfig` `PieceImpact = 60` y `ObjectivesConfig.ImpactMinDropStuds = 4` (objetivos.md y estimulos.md).
- Puertas interactuables.
- Audio.
- Lógica de los servicios que leen los marcadores.
- Tamaño del radio de detección de la criatura.
