# Spec: Mapa greybox en dos actos (F1-1, revisión 2)

Estado: propuesta para aprobar (2026-11-27). Sustituye al layout de la revisión 1 (torre en colina, pantano y mina-nido). Fuente: GDD.md (0, 2, 3, 5), objetivos.md, recoleccion-inventario.md, estimulos.md, ciclo-partida.md, construccion.md, arquitectura.md (Workspace/Map, Workspace/Markers), WorldConfig.luau.

Objetivo: un solo mapa greybox, construido por `tools/map/MapBuilder.luau` (determinista e idempotente), partido en dos territorios por un río infranqueable para los jugadores. El único paso es un puente roto que se reconstruye a mitad de partida (Fase 3). El mapa incluye las dos variantes del puente, todos los marcadores que piden las specs y los marcadores de preparación para la anomalía y la narrativa ambiental.

Prioridad: rendimiento y coherencia por encima del tamaño. El mapa es más pequeño que en la revisión 1.

## 0. Convenciones

- Ejes: Y arriba. X+ = este, Z- = norte, Z+ = sur (convención de Roblox: el frente por defecto mira a Z-).
- Origen (0, 0, 0) = centro de la caseta de radio. El suelo general está en Y = 0 en los dos territorios.
- Distancias en studs, medidas en planta (XZ) desde el origen.
- Las coordenadas son de diseño greybox; si un ajuste visual lo exige se pueden mover hasta 8 studs sin cambiar esta spec, pero las distancias a la base no deben variar más de un 10 %.
- Resolución del Terrain: celdas de 4. Los huecos excavados se dimensionan en múltiplos de 4 y con un mínimo de 8 de ancho.
- Paleta greybox: edificios en grises (`Medium stone grey`, `Dark stone grey`), madera en `Brown`, vegetación normal en verdes apagados, vegetación anómala en grises violáceos y verdes azulados, marcadores invisibles. Sin cambiar colores globales de materiales de Terrain.

## 1. Tamaño, territorios y base

- Terreno: X de -720 a 720, Z de -800 a 400 (1440 x 1200).
- Área jugable: X de -600 a 600, Z de -760 a 360. Muros invisibles en `Map/Limites` en los 4 bordes (altura 300). Montañas y bosque cierran la vista antes del muro.
- `WorldConfig.MapBounds`: `{ MinX = -600, MaxX = 600, MinZ = -760, MaxZ = 360, MinY = -60, MaxY = 300 }`. `MinY` baja a -60 por los sótanos del complejo.

| Territorio | Extensión | Contenido |
|---|---|---|
| Inicial (acto 1) | Al sur del río (Z > -230) | Base (Safe Zone), Ciudad abandonada con gasolinera, Mina, Torre (secundaria), bosque normal |
| Avanzado (acto 2) | Al norte del río (Z < -290) | Distrito industrial, Bosque anómalo, Complejo científico (nido en los sótanos) |

### Base (claro)

Sin cambios respecto a la revisión 1.

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Claro | centro (0, 0, 0) | radio 60 sin árboles | Grass plano en Y = 0 |
| Caseta de radio | centro (0, 0, 0) | 16 x 10 x 12 (X -8..8, Z -6..6) | Puerta al sur (Z = 6, X -2..2). Ventanas en norte, este y oeste |
| Mesa de la radio | (0, 0, -4) | 6 x 3 x 2 | Pegada a la pared norte |
| Radio | (0, 3.5, -4) | modelo 4 x 2 x 2 | Fija, indestructible, 4 sockets visuales |
| Fogata (socket) | (0, 0, 18) | 4 x 1 x 4 | Único `CampfireSocket` |
| BaseSpawn | (-8, 0, 18) | 8 x 1 x 8 | Lugar del `SpawnLocation` (sección 10) |
| Estante base | (-6, 0, -4) | 2 x 5 x 4 | Decorado, lado oeste. No solapa el contenedor de loot |
| Loot de base | (6, 0, -4) | contenedor | `LootSpawns/Base_01` (2 Pila), en el suelo, lado este |
| BuildZone Base | centro (0, 0, 0) | 96 x 96 (X -48..48, Z -48..48), cota 0 | 12 x 12 celdas de 8 |

Salidas del claro: norte (cortafuegos al puente), este (sendero a la ciudad) y oeste (sendero a la mina). Las ventanas norte miran por el cortafuegos al puente y, al otro lado del río, a la chimenea del distrito industrial.

## 2. Río y puente

### 2.1 Río (barrera del acto 1)

Garganta que cruza el mapa de oeste a este. Nace al pie de la montaña oeste y se pierde en la cordillera este.

- Polilínea del centro: (-470, -265) -> (-300, -245) -> (-120, -270) -> (0, -262) -> (150, -250) -> (380, -285) -> (720, -260).
- Agua: 40 de ancho, superficie en Y = -14, fondo de Mud y Rock en Y = -24.
- Orilla sur: talud transitable (FillWedge o escalonado) de Y 0 a Y -14 en unos 16 studs. Quien cae al río puede volver al territorio inicial por cualquier punto.
- Orilla norte: pared vertical de Rock de Y -24 a Y 0, sin repisas. No se puede salir del agua por el norte.
- `Map/Rio/Barrera_NN`: Parts invisibles (`Transparency = 1`, `CanCollide = true`, `CanQuery = false`, `CanTouch = false`) de 2 de grosor siguiendo el borde norte, de Y -30 a Y 300, de X -720 a 720 (también sobre la montaña oeste y la cordillera este, para que no se pueda rodear el río). Hueco de 14 de ancho en el eje del puente (X -7..7). Tag `PlayerBarrier`.
- La barrera bloquea a los jugadores. La criatura principal la atraviesa: el grupo de colisión lo asigna AIService/WorldService en F4 (los enemigos no colisionan con `PlayerBarrier`). Hasta entonces bloquea a todo.
- Sonido futuro: rumor de agua constante a lo largo de la garganta; tapa pasos lejanos.

### 2.2 Puente

Puente de carretera de piedra y hormigón, volado (lore: control militar en la cabecera sur). Eje N-S en X = 0.

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Estribo sur | (0, 0, -226) | 14 x 2 x 12, cara superior en Y = 1 | Sobre el borde del talud |
| Tramo sur (roto) | Z -232..-246 | 10 x 1 x 14, cara superior en Y = 1 | Termina en borde quebrado |
| Pilares | (0, -14, -254) y (0, -14, -270) | 6 x 10 x 6 | Rotos: cima en Y = -9, por debajo de la calzada. Desde el agua se sube a la cima, pero no a la calzada |
| Tramo norte (roto) | Z -278..-292 | 10 x 1 x 14, cara superior en Y = 1 | Termina en borde quebrado |
| Estribo norte | (0, 0, -298) | 14 x 2 x 12, cara superior en Y = 1 | |
| Escombros | en el agua entre Z -246 y -278 | 3-4 losas inclinadas | Decorado, `CanCollide = true`, cima por debajo de Y = -10 |
| Hueco | Z -246..-278 | 32 studs | Imposible de saltar |
| Control militar | cabecera sur, (0, 0, -205) | barreras, sacos, vehículo volcado | Lore A1-03. Deja libre un paso de 6 en el eje |

Variante construida (`PuenteConstruido`): tramo central de tablones y vigas de 10 x 1 x 32 (Z -246..-278, cara superior en Y = 1) con barandillas de 1 de alto a ambos lados. MapBuilder la construye y la guarda en `ServerStorage/MapVariants/PuenteConstruido` (Model, PrimaryPart `Pivot` en (0, 1, -262)). No está en Workspace por defecto.

Estado del puente:
- `Workspace/Map/Puente` lleva el atributo `BridgeBuilt` (boolean, `false` por defecto).
- Activar = clonar `PuenteConstruido` dentro de `Map/Puente/Construido` y poner `BridgeBuilt = true`. Desactivar = destruir `Map/Puente/Construido` y poner `false`. WorldService lo resetea a roto al empezar cada run.
- La construcción por tramos es de Fase 3 (construccion.md). En F1 solo existe el comando de debug en Studio (objetivos.md).

## 3. Zonas

Orden de ritmo:
- Acto 1 (orden libre): Ciudad/gasolinera (cerca, tutorial) y Mina (oscuridad, dificultad media). Torre opcional como mirador.
- Puente: reconstruirlo exige los recursos del acto 1 (construccion.md); cae hacia la mitad de la partida por coste, no por tiempo.
- Acto 2 (orden libre): Distrito industrial (pieza pesada, escolta larga) y Complejo científico (nido). El Bosque anómalo está entre los dos y alrededor del complejo.

| Zona (ZoneId) | Territorio | Centro de zona | Distancia | Volumen de zona (centro, tamaño) | Pieza |
|---|---|---|---|---|---|
| Base | Inicial | (0, 0, 0) | 0 | (0, 10, 0), 100 x 40 x 100 | - |
| Ciudad | Inicial | (300, 0, 0); gasolinera en (230, 0, -40) | 300 (gasolinera 233) | (300, 15, 0), 220 x 50 x 200 | Bateria |
| Torre | Inicial | (-120, 20, -150) | 192 | (-120, 30, -150), 120 x 80 x 120 | - (secundaria) |
| Mina | Inicial | entrada (-380, 0, -40) | 382 (entrada) | (-480, 15, -30), 250 x 40 x 150 | Cristal |
| Industrial | Avanzado | (280, 0, -450) | 530 | (280, 20, -450), 240 x 60 x 200 | Antena |
| BosqueAnomalo | Avanzado | (0, 0, -560) | 560 | (0, 20, -560), 300 x 60 x 300 | - |
| Complejo | Avanzado | (-300, 0, -580) | 652 | (-300, 5, -580), 160 x 90 x 160 (Y -40..50) | Transceptor |

Fuera de cualquier volumen = `Bosque`. Los volúmenes sirven para revelar piezas (objetivos.md) y para el ambiente por zona en el cliente. Las zonas no se solapan; entre BosqueAnomalo y Complejo queda una franja de transición (X -220..-150).

### 3.1 Ciudad abandonada con gasolinera (~230-300, tutorial)

Pueblo evacuado a toda prisa. La gasolinera está en la entrada oeste, sobre la carretera que baja al puente.

| Elemento | Posición (centro) | Tamaño | Notas |
|---|---|---|---|
| Calle mayor | X = 262, Z de -80 a 110 | 16 de ancho | Asphalt. Al norte sigue como carretera al puente (sección 5) |
| Calle transversal | Z = 15, X de 262 a 400 | 12 de ancho | Asphalt |
| Tienda | (220, 0, -50) | 28 x 10 x 18 | Puerta este. Almacén al fondo (X 206..214) con tabique y hueco de puerta. 3 filas de estanterías |
| Taller | (220, 0, -18) | 14 x 10 x 14 | Hueco de cierre metálico al este |
| Marquesina | (246, 12, -30) | 24 x 1 x 16 sobre 4 columnas | Surtidores en (246, 0, -34) y (246, 0, -26) |
| Edificios | (300, 0, -60) 30x18x24; (300, 0, -10) 24x14x30; (300, 0, 45) 30x22x24; (350, 0, -60) 26x12x26; (355, 0, -10) 30x26x30; (350, 0, 55) 24x14x24 | | Cajas huecas solo en planta baja, con 1-2 huecos de puerta. El de 26 de alto es la referencia de la ciudad |
| Coches | 8 en la calle mayor y la carretera, en fila hacia el norte | 6 x 5 x 12 | Evacuación cortada (lore A1-01). Uno junto a los surtidores en (252, 0, -30) |
| Barricadas | (262, 0, -85) y (330, 0, 15) | vallas y sacos | Cortan el paso de coches, no de personas |
| Tablón de avisos | (234, 0, -40) | 4 x 3 x 0.5 | Hojas de evacuación (lore A1-02) |
| Escombros | 3 montones de Rock en (320, 0, 80), (380, 0, -30) y (390, 0, 70) | | Rocas recolectables alrededor |

Las puertas metálicas no son interactuables todavía; son huecos.

### 3.2 Torre (secundaria, mirador)

Torre de vigilancia forestal en una loma junto al río. No tiene pieza ni loot; da visión del puente y del territorio avanzado.

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Loma | Terrain FillBall centro (-120, -100, -150), radio 120 | cima en Y = 20, pie de radio 66 | Grass con afloramientos de Rock. Sin árboles por encima de Y = 10 |
| Torre | patas en las esquinas de 10 x 10 centrado en (-120, 20, -150) | de Y 20 a 50 | 4 patas de 1.5 x 30 x 1.5 con riostras |
| Cabina | (-120, 50, -150) | 14 x 8 x 14, suelo con la cara superior en Y = 50 | Barandilla de 3. Techo en Y = 59 |
| Escalera | cara sur, TrussPart | de Y 20 a 50 | |
| Caseta de herramientas | (-104, 20, -142) | 8 x 7 x 8 | Escondite. Prismáticos y mapa marcado (lore A1-05) |

Línea de visión: desde la cabina se ven el claro de la base, el puente, la chimenea del distrito industrial y la linde del bosque anómalo.

### 3.3 Mina (~380-600, dificultad media)

Mina de mineral abandonada al pie de la montaña oeste. Ya no es el nido: es exploración subterránea, oscuridad y recursos minerales. Conserva el trazado de la revisión 1 girado 90 grados (la boca mira al este y las galerías avanzan hacia el oeste).

Montaña oeste: Terrain FillBall de Rock con centro (-737, -127, -40) y radio 377. El pie queda en X = -380 frente a la entrada.

| Espacio excavado | Centro | Tamaño (X x Y x Z) | Notas |
|---|---|---|---|
| Túnel A (entrada) | (-402, 6, -40) | 76 x 12 x 12 (X -364..-440) | Marcos de madera cada 12. Nicho lateral (-412, 4, -48) de 8 x 8 x 8 |
| Galería | (-460, 7, -40) | 32 x 14 x 40 | Bifurcación. Vagoneta y rieles |
| Túnel B1 | (-460, 5, 0) | 12 x 10 x 40 | Hacia el sur |
| Túnel B2 | (-496, 5, 20) | 60 x 10 x 12 | Hacia el oeste |
| Pozo | (-540, 10, 20) | 32 x 20 x 32 | Pozo vertical derrumbado de 8 x 30 x 8 hacia arriba, sin salida |
| Túnel C | (-518, 6, -40) | 84 x 12 x 12 | De la galería a la caverna |
| Caverna de cristal | (-580, 9, -60) | 40 x 18 x 52 | Cámara más profunda. Vetas de cristal (Parts de `Glass` pálido, sin luz) |
| Gatera 1 | (-540, 4, -8) | 8 x 8 x 24 | Del pozo hacia el norte |
| Gatera 2 | (-560, 4, -20) | 40 x 8 x 8 | Hacia el oeste |
| Gatera 3 | (-580, 4, -28) | 8 x 8 x 16 | Entra a la caverna por el sur |
| Campamento minero | exterior, (-350, 0, -10) | caseta 8 x 7 x 8, cajas, carretilla | Lore A1-04 |

El circuito galería -> pozo -> gateras -> caverna -> túnel C -> galería forma un bucle. Sin fuentes de luz dentro. De noche la criatura puede patrullar la mina (ruta `Mina`); de día está vacía.

### 3.4 Distrito industrial (~470-560, pieza pesada)

Naves y oficinas de una empresa que abastecía al complejo. Es la referencia del acto 2: su chimenea se ve desde la base.

| Elemento | Posición (centro) | Tamaño | Notas |
|---|---|---|---|
| Nave principal | (300, 0, -470) | 60 x 24 x 40 (X 270..330, Z -490..-450) | Planta abierta con huecos de puerta N y S, máquinas (bloques). Azotea en Y = 24 con pretil de 1.5 y un hueco de 4 en el lado sur, sobre el patio de carga |
| Escalera de incendios nave | pared este (X = 330), TrussPart | de Y 0 a 24 | Único acceso a la azotea |
| Patio de carga | (300, 0, -435) | 50 x 30, Asphalt | Zona de caída de la Antena: sin obstáculos en radio 6 de (300, 0, -446) |
| Oficinas | (220, 0, -500) | 24 x 16 x 20 | Planta baja con mesas. Azotea en Y = 16 con pretil y hueco de 4 en el lado este |
| Escalera de oficinas | pared oeste (X = 208), TrussPart | de Y 0 a 16 | Zona de caída: (236, 0, -500) |
| Almacén abierto | (230, 0, -410) | 40 x 12 x 24, abierto al sur | Camión (8 x 8 x 18) dentro |
| Chimenea | (340, 0, -520) | cilindro de 6, alto 70 | Referencia de lejos |
| Contenedores | 10 en 3 pilas alrededor de (360, 0, -420) | 8 x 8 x 20 | Con el logotipo del complejo y destino rotulado (lore A2-01). Uno abierto |
| Valla | perímetro con portón al oeste (165, 0, -430) | 2 de alto | Cuello de botella de salida con la Antena |
| Línea eléctrica | torres de 30 de alto cada 80 studs: (330, -560) -> (200, -640) -> (40, -680) -> (-120, -660) -> (-230, -610) | | Une el distrito con el complejo bordeando el bosque anómalo (lore A2-02) |

### 3.5 Bosque anómalo (~560)

Bosque alterado por los experimentos. Rodea el sendero corto al complejo. Se prepara para mecánicas futuras (interferencia electromagnética, visibilidad reducida, terror auditivo) sin implementarlas.

| Elemento | Posición | Tamaño | Notas |
|---|---|---|---|
| Árboles anómalos | dentro del volumen, densidad media | 3 variantes: tronco torcido inclinado 8-20 grados, copa partida, árbol seco con ramas en ángulo | Grises violáceos y verdes azulados. Tope 220 |
| Hongos bioluminiscentes | 40 grupos en raíces y troncos caídos | bolas de 1-2 de `Neon` cian/verde azulado | Solo 12 llevan `PointLight` (Range 10, Brightness 0.6). Sin más luces |
| Campamento de investigación | (0, 0, -520) | 2 tiendas (cuñas), mesa, generador, cajas | Lore A2-03 |
| Postes de sensores | (-60, -470), (70, -480), (60, -640), (-80, -630) | poste de 6 con caja | Lore A2-04 |
| Árboles marcados | 6 cerca del sendero | estacas y cinta | Lore A2-05 |
| Todoterreno abandonado | (-60, 0, -480) | 6 x 5 x 12 | En el sendero, puertas abiertas |
| Terreno | manchas de Ground y Mud sobre el Grass | ReplaceMaterial | Sin cambiar el color global de ningún material |

Niebla y efectos: sin tocar Lighting. El volumen `AnomalyZone/BosqueAnomalo` deja preparados niebla local, interferencia y audio para el cliente (sección 8).

### 3.6 Complejo científico (~650, nido)

Instalación cercada. En superficie es una fachada de laboratorio; abajo están las instalaciones profundas donde duerme la criatura.

Superficie:

| Elemento | Posición (centro) | Tamaño | Notas |
|---|---|---|---|
| Cerca | perímetro 140 x 140 centrado en (-300, -580) | 3 de alto | Portón este en (-230, 0, -580), roto |
| Garita | (-226, 0, -560) | 6 x 8 x 6 | Escondite |
| Laboratorio | (-300, 0, -580) | 40 x 14 x 30 (X -320..-280, Z -595..-565) | Sala de control con pantallas apagadas (lore A2-07). Puerta de seguridad oeste sellada desde dentro (lore A2-06). Escalera interior al sótano 1 en (-290, 0, -590) |
| Generadores | (-340, 0, -530) | 16 x 10 x 12 | Escondite |
| Antena parabólica | (-260, 0, -630) | plato de 10 | |
| Depósito de agua | (-350, 0, -630) | torre de 20 | |

Subterráneo (Terrain excavado con Air y forrado con Parts: suelo, paredes y techo):

| Espacio | Centro | Tamaño (X x Y x Z) | Notas |
|---|---|---|---|
| Escalera 1 | de (-290, 0, -590) a (-290, -18, -626) | 8 de ancho | Tramos con rellano, sin TrussPart |
| Sótano 1 | (-300, -12, -600) | 60 x 12 x 48, suelo en Y = -18 | Pasillo y 3 laboratorios. Contenedores de muestras vacíos y rotos (lore A2-08) |
| Escalera 2 | de (-320, -18, -616) a (-320, -40, -656) | 8 de ancho | |
| Sótano 2 | pasillo (-300, -34, -650), 60 x 12 x 12, suelo en Y = -40 | | Lleva a la sala de contención |
| Sala de contención (nido) | (-310, -31, -640) | 50 x 18 x 40 (Y -40..-22) | Cristal roto y estructuras retorcidas. Coincide con el volumen `Nest` |

Sin luz en el subterráneo.

## 4. Puntos de aparición de piezas

Ruta: `Workspace/Markers/ObjectiveSpawns/<PieceId>/01..03`. Parte de 2 x 1 x 2 con la cara inferior apoyada en el suelo indicado.

| PieceId | Zona | 01 | 02 | 03 |
|---|---|---|---|---|
| Bateria | Ciudad | Almacén de la tienda (210, 0, -54) | Taller (218, 0, -14) | Detrás del coche de la carretera (264, 0, -88) |
| Cristal | Mina | Galería (-468, 0, -52) | Pozo (-546, 0, 24) | Caverna de cristal (-592, 0, -80) |
| Antena | Industrial | Azotea de la nave (300, 24, -470) | Azotea de las oficinas (220, 16, -500) | Almacén, junto al camión (236, 0, -412) |
| Transceptor | Complejo | Sala de control (-306, 0, -576) | Sótano 1 (-320, -18, -596) | Sótano 2, junto al nido (-296, -40, -626) |

Distancias reales a la base: Bateria de 215 a 280, Cristal de 470 a 600, Antena de 470 a 560, Transceptor de 650 a 700. Transceptor/03 está a 20 studs de donde duerme la criatura.

Antena (objetivos.md): quien la carga no puede usar escaleras de mano. Desde 01 y 02 se suelta por el hueco del pretil al patio de carga o junto a las oficinas y emite `PieceImpact`. 03 está en el suelo y no hace ruido al recogerla, pero queda lejos del portón.

## 5. Caminos, referencias, visión, cuellos de botella y escondites

### 5.1 Caminos

Se pintan con `Terrain:ReplaceMaterial` sobre el terreno ya creado.

| Id | Territorio | Recorrido | Ancho | Material | Notas |
|---|---|---|---|---|---|
| Cortafuegos | Inicial | (0, -48) -> (0, -220) | 20 sin árboles; franja de Ground de 6 | Ground | De la base al puente. Línea de visión |
| Sendero Ciudad | Inicial | (44, 0) -> (150, -20) -> (240, -40) | 8 | Ground | Tutorial |
| Carretera | Inicial | (262, 110) -> (262, -80) -> (150, -170) -> (30, -212) -> (0, -220) | 16 | Asphalt | Calle mayor de la ciudad hasta el puente |
| Sendero Mina | Inicial | (-44, 10) -> (-160, -10) -> (-300, -40) -> (-364, -40) | 6 | Ground | |
| Subida a la torre | Inicial | (-40, -110) -> (-104, -142) | 6 | Ground | Sale del cortafuegos |
| Carretera norte | Avanzado | (0, -304) -> (0, -370) -> (120, -400) -> (165, -430) | 16 | Asphalt | Del puente al portón industrial |
| Sendero anómalo | Avanzado | (0, -370) -> (-40, -460) -> (-120, -540) -> (-230, -580) | 6 | Ground | Corto, por dentro del bosque anómalo |
| Pista de servicio | Avanzado | (280, -550) -> (200, -630) -> (40, -670) -> (-120, -650) -> (-230, -600) | 8 | Ground | Larga, bajo la línea eléctrica, bordea el bosque anómalo |

Al complejo se llega por el sendero anómalo (corto y peligroso) o por la pista de servicio desde el distrito (larga y abierta).

### 5.2 Referencias visibles de lejos

- Chimenea del distrito industrial (70 de alto): referencia del acto 2, visible desde la base, el cortafuegos y la torre.
- Torre de vigilancia sobre la loma: referencia del acto 1.
- Edificio de 26 de alto en la ciudad.
- Montaña oeste (mina) y torres de la línea eléctrica.
- De noche, la referencia de la base es la fogata. Los hongos del bosque anómalo se ven desde el puente como un resplandor débil.

### 5.3 Líneas de visión

- Ventanas norte de la caseta -> cortafuegos -> puente -> carretera norte.
- Cabina de la torre -> base, puente, chimenea y linde del bosque anómalo.
- Azotea de la nave -> puente y río: quien baja la Antena ve el camino de vuelta.
- El bosque anómalo no tiene líneas largas.

### 5.4 Cuellos de botella

| Id | Posición | Qué obliga |
|---|---|---|
| Puente | sección 2.2 | Único paso entre territorios. 10 de ancho, 80 de largo sobre la garganta |
| Portón industrial | (165, 0, -430) | Salida con la Antena |
| Escaleras de incendios | sección 3.4 | Lentas, sin cobertura, no admiten Antena |
| Túnel A de la mina | sección 3.3 | Única entrada |
| Gateras de la mina | sección 3.3 | 8 x 8, estrecho |
| Escaleras del complejo | sección 3.6 | Única ruta al nido y de vuelta |

### 5.5 Escondites

Ruta: `Workspace/Markers/Hideouts/<Nombre>`, tag `Hideout`, atributo `ZoneId`.

| Nombre | Posición |
|---|---|
| Ciudad_Almacen | (210, 0, -54) |
| Ciudad_Taller | (220, 0, -18) |
| Matorral_Este | (70, 0, -60) |
| Matorral_Oeste | (-80, 0, 60) |
| Torre_Caseta | (-104, 20, -142) |
| Mina_Nicho | (-410, 0, -46) |
| Industrial_Oficinas | (216, 0, -500) |
| Complejo_Garita | (-226, 0, -560) |
| Complejo_Generadores | (-340, 0, -530) |

Los matorrales son grupos de 6 bolas de 6 a 8 studs con `CanCollide = false`.

## 6. Enemigos: aparición, patrulla y cruce del río

EnemiesConfig está vacío y enemigo.md no existe. Estos puntos son la colocación; su uso lo decide F4.

### 6.1 Aparición

Ruta: `Workspace/Markers/EnemySpawns`, tag `EnemySpawn`, atributo `EnemyKind`. El `EnemyKind` de los acechadores sigue siendo `AcechadorMenor` (prefab existente); en diseño se llaman acechadores anómalos.

| Nombre | EnemyKind | Posición |
|---|---|---|
| CriaturaPrincipal_01 | CriaturaPrincipal | (-310, -40, -645), en la sala de contención |
| AcechadorMenor_01 | AcechadorMenor | (-40, 0, -640), bosque anómalo |
| AcechadorMenor_02 | AcechadorMenor | (60, 0, -600) |
| AcechadorMenor_03 | AcechadorMenor | (-100, 0, -560) |

Volumen `Workspace/Markers/Nest`: centro (-310, -31, -640), 50 x 18 x 40.

Regla de territorio (para F4): los acechadores no nadan. Sin puente construido no pueden entrar en el territorio inicial; con el puente construido lo cruzan. La criatura principal cruza el río a nado desde la noche 1.

### 6.2 Cruce de la criatura

Ruta: `Workspace/Markers/CreatureCrossings/<CrossingId>_<Side>`, tag `CreatureCrossing`, atributos `CrossingId` y `Side` ("Sur" o "Norte"). Son los puntos donde la criatura entra y sale del agua; F4 resuelve la trepada de la orilla norte. Ninguno a menos de 60 studs del puente.

| CrossingId | Sur (X, Z) | Norte (X, Z) |
|---|---|---|
| Oeste | (-230, -232) | (-230, -298) |
| Centro | (90, -226) | (90, -292) |
| Este | (300, -245) | (300, -310) |

### 6.3 Patrulla

Ruta: `Workspace/Markers/PatrolPoints/<RouteId>/NN`. Tag `PatrolPoint`, atributos `RouteId` y `Order`. La Y sale de un raycast contra la superficie; en rutas subterráneas (Mina y los puntos bajo tierra de Complejo) el raycast parte de 6 studs por encima del suelo del túnel o sótano, no del cielo.

| RouteId | Para | Puntos en orden (X, Z) |
|---|---|---|
| Bosque | Criatura, rodea la base | (0, -125), (110, -90), (120, 70), (40, 140), (-90, 130), (-150, 10), (-110, -100) |
| Exterior | Criatura, territorio inicial | (0, -200), (180, -160), (262, -40), (200, 110), (-120, 130), (-300, -20), (-200, -200) |
| Mina | Criatura dentro de la mina | (-390, -40), (-460, -40), (-540, 20), (-560, -20), (-580, -60) |
| Complejo | Criatura, del nido a la superficie | (-310, -645) Y -40, (-300, -650) Y -40, (-300, -600) Y -18, (-300, -585) Y 0, (-230, -580), (-120, -540) |
| BosqueAnomalo | Acechadores | (0, -440), (90, -500), (100, -620), (0, -680), (-110, -640), (-120, -500) |

## 7. Recursos recolectables

Los árboles y rocas recolectables son clones de los prefabs `Arbol` y `Roca` de `ServerStorage/Prefabs`, creados por el servidor sobre `ResourceSpawns`. El mapa solo pone los marcadores. PrefabBuilder no cambia.

Ruta: `Workspace/Markers/ResourceSpawns/<Kind>_NNN`. Tag `ResourceSpawn`, atributos `Kind` ("Arbol" o "Roca") y `ZoneId`. El total se mantiene en 110 (68 + 42); se concentra en el acto 1 porque el puente se paga con ellos.

| Zona | Arbol | Roca | Dónde |
|---|---|---|---|
| Base | 16 | 6 | Anillo de radio 56 a 96, fuera de la BuildZone |
| Bosque (inicial) | 30 | 6 | A 8-20 studs de los caminos del territorio inicial |
| Ciudad | 4 | 6 | Rocas en los montones de escombros |
| Torre | 4 | 4 | Árboles al pie de la loma; rocas en los afloramientos |
| Mina | 0 | 12 | 4 fuera de la entrada; 8 en galería, pozo y caverna |
| Industrial | 2 | 4 | Junto a la valla y el patio |
| BosqueAnomalo | 12 | 2 | Junto al sendero anómalo |
| Complejo | 0 | 2 | Dentro de la cerca |
| Total | 68 | 42 | 110 nodos (88 en el acto 1) |

Arbustos de bayas (F2, comida): 24 marcadores más con `Kind = "Arbusto"` (`Arbusto_001..024`), solo en el bosque normal del territorio inicial: 20 en `Bosque` (a 8-30 studs de los caminos del territorio inicial) y 4 en `Torre` (pie de la loma). Ninguno en el claro de la base ni en el territorio avanzado. Prefab `Arbusto` de PrefabBuilder (recoleccion-inventario.md). Con ellos `ResourceSpawn` pasa a 134 (68 Arbol, 42 Roca, 24 Arbusto).

Reglas de colocación (deterministas, semilla fija): separación mínima 8; ninguno a menos de 6 del centro de un camino, sobre el agua o en la garganta, en una NoBuildZone ni a menos de 4 de un marcador de pieza, loot o spawn. La Y sale de un raycast contra el terreno y las Parts del mapa.

### Bosque decorativo (no recolectable)

En `Map/Bosque`. Cierra la vista y da escondites. Conserva la variación de la revisión 1:
- Rejilla de 18 con desplazamiento de hasta 8, giro en Y y escala 0.8-1.3, todo con semilla fija.
- 3 variantes: alto y estrecho, copa ancha y baja, copa en dos niveles gris verdosa.
- Probabilidad 0.55 a menos de 150 studs de un camino o zona, 0.15 más lejos. Tope de 1400 árboles (antes 2500).
- Exclusiones: claro de la base (radio 60), cortafuegos (|X| < 12, Z -220..-48), a menos de 10 de un camino, garganta del río más 6, volúmenes de zona, loma por encima de Y = 10, montañas, cerca del complejo.
- Dentro de `BosqueAnomalo` no hay árboles normales: solo los anómalos (sección 3.5).

## 8. Anomalía y narrativa ambiental

### 8.1 AnomalyZone

Ruta: `Workspace/Markers/AnomalyZones/<AnomalyId>` (Parts, volumen). Tag `AnomalyZone`. Atributos:
- `AnomalyId` (string);
- `Intensity` (number 0..1);
- `FogHint`, `EMHint`, `AudioHint` (boolean): qué efectos podrá aplicar el cliente en el futuro;
- `Propagation` (boolean): volumen reservado para la propagación visual alrededor del puente.

Ningún sistema los usa todavía.

| AnomalyId | Centro | Tamaño | Intensity | Fog / EM / Audio | Propagation |
|---|---|---|---|---|---|
| BosqueAnomalo | (0, 20, -560) | 300 x 60 x 300 | 1.0 | sí / sí / sí | no |
| Complejo | (-300, 5, -580) | 160 x 90 x 160 | 0.8 | no / sí / sí | no |
| PuenteNorte | (0, 10, -330) | 120 x 40 x 60 | 0.3 | sí / no / sí | sí |
| PuenteSur | (0, 10, -200) | 120 x 40 x 60 | 0.0 | sí / no / sí | sí |

`PuenteSur` empieza a 0: es donde se verá avanzar la anomalía en el territorio inicial cuando exista esa mecánica.

### 8.2 Puntos de narrativa

Ruta: `Workspace/Markers/LorePoints/<LoreId>`. Tag `LorePoint`, atributos `LoreId`, `ZoneId` y `Act` (1 o 2). Cada punto tiene al lado su atrezo greybox en el `Map` de su zona. Sin textos legibles en esta fase: los textos, si los hay, llegarán con su propia spec.

Regla: el acto 1 muestra consecuencias; el acto 2 apunta a una investigación previa que une el complejo, el distrito y el bosque, sin revelar el experimento ni el origen de la criatura.

| LoreId | Act | Zona | Posición | Qué se ve |
|---|---|---|---|---|
| A1-01 | 1 | Ciudad | (262, 0, -60) | Coches abandonados en fila hacia el puente, puertas abiertas |
| A1-02 | 1 | Ciudad | (234, 0, -40) | Tablón con hojas de evacuación |
| A1-03 | 1 | Bosque | (0, 0, -205) | Control militar destruido en la cabecera sur del puente |
| A1-04 | 1 | Mina | (-350, 0, -10) | Campamento minero abandonado a medio turno |
| A1-05 | 1 | Torre | (-104, 20, -142) | Prismáticos y mapa con marcas apuntando al norte |
| A2-01 | 2 | Industrial | (360, 0, -420) | Contenedores con el logotipo del complejo y su destino |
| A2-02 | 2 | Industrial | (330, 0, -560) | Arranque de la línea eléctrica hacia el complejo |
| A2-03 | 2 | BosqueAnomalo | (0, 0, -520) | Campamento de investigación con instrumental |
| A2-04 | 2 | BosqueAnomalo | (70, 0, -480) | Poste de sensores |
| A2-05 | 2 | BosqueAnomalo | (-40, 0, -460) | Árboles marcados con números y estacas |
| A2-06 | 2 | Complejo | (-320, 0, -580) | Puerta de seguridad sellada desde dentro |
| A2-07 | 2 | Complejo | (-306, 0, -576) | Sala de control con pantallas apagadas |
| A2-08 | 2 | Complejo | (-300, -18, -610) | Contenedores de muestras vacíos y rotos |

## 9. Terrain y Parts

| Con Terrain | Con Parts |
|---|---|
| Suelo general (Grass, Y = 0) | Caseta, mesa, radio y estante |
| Loma de la torre (FillBall, Grass y Rock) | Torre, cabina, escalera y caseta |
| Montaña oeste y cordilleras (FillBall de Rock y Slate) | Tienda, taller, marquesina, edificios, coches, barricadas |
| Garganta del río (Air, Water, Mud, Rock; talud sur con FillWedge) | Puente roto, control militar, barrera del río, `PuenteConstruido` |
| Interior de la mina (Air) | Marcos, vagoneta, rieles, vetas de cristal, campamento minero |
| Hueco de los sótanos del complejo (Air) | Naves, oficinas, almacén, chimenea, contenedores, valla, línea eléctrica |
| Montones de escombros (Rock) | Cerca, garita, laboratorio, sótanos (suelo, paredes, techo, escaleras), parabólica, depósito |
| Caminos (ReplaceMaterial con Ground y Asphalt), manchas del bosque anómalo (Ground y Mud) | Bosque decorativo, árboles anómalos, hongos, campamento, sensores, matorrales, muros límite y marcadores |

Cordilleras de borde (FillBall de Rock):
- norte (0, -300, -1010), radio 400 (pie en Z -746);
- este (820, -300, 0), radio 400 (pie en X 556);
- sur (0, -300, 640), radio 400 (pie en Z 376);
- esquinas (600, -250, -760) y (600, -250, 360), radio 330.

El oeste lo cierra la montaña de la mina; la esquina noroeste, una FillBall (-640, -250, -760) de radio 330.

### Presupuesto de rendimiento

- Map completo: menos de 9000 BaseParts (sin contar Terrain).
- Bosque decorativo: tope 1400; árboles anómalos: tope 220; hongos: 40 grupos.
- Luces: como mucho 12 `PointLight` en todo el mapa (hongos). Ninguna sombra dinámica añadida.
- Edificios: solo planta baja con interior; plantas superiores macizas o inexistentes salvo las azoteas pedidas.
- `task.wait()` tras cada bloque de terreno de 200 x 200 y cada 200 árboles.

## 10. Jerarquía, nombres y tags

La jerarquía sigue arquitectura.md y es la fuente de verdad. Los tags duplican los marcadores para consultarlos con `GetTagged`.

```
Workspace
  SpawnLocation               (único; en BaseSpawn, invisible, sin Decal, Neutral, CanCollide = false)
  Map                         (Folder; lo reconstruye MapBuilder)
    Zones                     (Folder) Base, Ciudad, Torre, Mina, Industrial, BosqueAnomalo, Complejo   tag MapZone, attr ZoneId
    Base                      (Folder) Caseta (Model), Radio (Model), Estante
    Ciudad                    (Folder) Gasolinera (Tienda, Taller, Marquesina, Surtidores), Edificios, Coches, Barricadas, Escombros, Tablon
    Torre                     (Folder) Torre (Model), CasetaHerramientas
    Mina                      (Folder) Soportes, Vagoneta, Rieles, Portal, Vetas, Campamento
    Rio                       (Folder) Barrera_NN                               tag PlayerBarrier
    Puente                    (Folder, attr BridgeBuilt) Roto (Estribos, Tramos, Pilares, Escombros), ControlMilitar, Construido (solo si BridgeBuilt)
    Industrial                (Folder) NavePrincipal, Oficinas, Almacen, Chimenea, Contenedores, Valla, Escaleras
    LineaElectrica            (Folder) Torre_NN, Cables
    BosqueAnomalo             (Folder) Arboles, Hongos, Campamento, Sensores, Marcas, Todoterreno
    Complejo                  (Folder) Cerca, Garita, Laboratorio, Generadores, Parabolica, Deposito, Sotano1, Sotano2, Contencion
    Caminos                   (Folder)
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
    PatrolPoints/<RouteId>/NN                  tag PatrolPoint, attr RouteId, Order
    Hideouts/<Nombre>                          tag Hideout, attr ZoneId
    BridgeSite                (Part, volumen)  tag BridgeSite, attr BridgeId, Segments      (nuevo)
    BridgeEnds/Sur, Norte     (Parts)          tag BridgeEnd, attr Side                    (nuevo)
    CreatureCrossings/<CrossingId>_<Side>      tag CreatureCrossing, attr CrossingId, Side (nuevo)
    AnomalyZones/<AnomalyId>  (Parts, volumen) tag AnomalyZone, attr AnomalyId, Intensity, FogHint, EMHint, AudioHint, Propagation (nuevo)
    LorePoints/<LoreId>                        tag LorePoint, attr LoreId, ZoneId, Act     (nuevo)
  Runtime                     (no lo toca MapBuilder)
ServerStorage
  Prefabs                     (no lo toca MapBuilder)
  MapVariants/PuenteConstruido (Model; lo reconstruye MapBuilder)                         (nuevo)
```

### Radio

`Map/Base/Radio` es un Model con el atributo `InteractableId = "radio"` y 4 Parts `Socket_Bateria`, `Socket_Antena`, `Socket_Transceptor` y `Socket_Cristal`.

### BridgeSite y BridgeEnds

- `BridgeSite`: volumen sobre el hueco, centro (0, 1, -262), 14 x 12 x 32. Atributos `BridgeId = "Principal"`, `Segments = 3`. Fase 3 lo usa para validar la construcción por tramos.
- `BridgeEnds/Sur` en (0, 1, -232) y `BridgeEnds/Norte` en (0, 1, -292), 10 x 1 x 4, atributo `Side`. Son los bordes de los tramos rotos.

### LootSpawns

13 en total, como pide recoleccion-inventario.md (`ResourcesConfig.ZoneLoot`, 3 contenedores por zona de pieza): 3 por zona de pieza (`<ZoneId>_01..03`, 1 Pila y 2 Chatarra cada uno) y `Base_01` en el suelo de la caseta, lado este (6, 0, -4). La torre y el bosque anómalo no tienen loot.

| ZoneId | 01 | 02 | 03 |
|---|---|---|---|
| Ciudad | Mostrador (226, 0, -46) | Banco del taller (214, 0, -22) | Coche de los surtidores (252, 0, -36) |
| Mina | Nicho del túnel (-410, 0, -46) | Galería (-452, 0, -28) | Pozo (-532, 0, 12) |
| Industrial | Oficinas (216, 0, -496) | Nave (290, 0, -480) | Contenedor abierto (360, 0, -420) |
| Complejo | Garita (-226, 0, -560) | Laboratorio (-286, 0, -570) | Sótano 1 (-300, -18, -610) |

### WaterZones

`Rio_1` a `Rio_6`: cajas rotadas, una por tramo de la polilínea del río, de 44 de ancho, de Y -24.5 a Y -13.5.

### NoBuildZones

Sin cambios: Caseta (0, 5, 0) 24 x 12 x 20; PuertaCaseta (0, 5, 12) 8 x 12 x 12; Fogata (0, 5, 18) 12 x 12 x 12; BaseSpawn (-8, 5, 18) 16 x 12 x 16. Incluyen el margen de 4 de `WorldConfig.ProtectedRadiusStuds`.

### Propiedades comunes de marcadores y volúmenes

- `Anchored = true`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`, `Transparency = 1`.
- Los servicios leen posición y tamaño por matemática o consultas propias, nunca por `Touched`.
- Todo lo que está dentro de una zona lleva el atributo `ZoneId`.
- Excepción: `PlayerBarrier` sí colisiona (sección 2.1).

## 11. Notas de terror

- **Base:** segura pero ciega. Por las ventanas norte se ve el puente; de noche, lo que venga por el cortafuegos.
- **Río:** el rumor del agua tapa pasos. La criatura sale del agua por los cruces, no por el puente: de noche cualquier tramo de orilla es sospechoso.
- **Puente:** construirlo hace ruido (`BuildRepair` 45) junto al agua por donde cruza la criatura. Una vez en pie, también es la puerta de los acechadores.
- **Ciudad:** zona de aprendizaje. Puertas metálicas y contenedores (`MetalOpen` 30). Coches oscuros que a lo lejos parecen figuras.
- **Mina:** oscuridad total, 76 studs de túnel sin salida lateral, gateras y caverna. De día está vacía; de noche puede entrar la criatura.
- **Distrito industrial:** la azotea expone a quien baja la Antena; el impacto avisa a todo lo que haya cerca. Escolta larga hasta el puente.
- **Bosque anómalo:** luz que no es de la fogata, árboles que no son de aquí, silencio raro. Preparado para niebla, interferencia y audio.
- **Complejo:** bajar dos sótanos sin luz sabiendo que la criatura duerme abajo. Transceptor/03 a 20 studs del nido.
- **Sonido futuro (sin marcadores en esta tarea):** río, viento en la torre y en la azotea, goteo en la mina, zumbido eléctrico en la línea, silencio con crujidos en el bosque anómalo, ventilación muerta en los sótanos.

## 12. MapBuilder (tools/map/MapBuilder.luau)

- `--!strict`. Se ejecuta en Studio con `execute_luau`, en modo Edit, nunca en Play.
- Idempotente: al empezar borra `Workspace.Baseplate` si existe. Si la sección es `"All"` o `Terreno`: `Workspace.Terrain:Clear()` y destruye `Workspace.Map`, `Workspace.Markers` y `ServerStorage.MapVariants`. Si no, limpia solo su propia carpeta. No toca `Workspace.Runtime`, Lighting ni `ServerStorage.Prefabs`.
- Tras crear los marcadores deja un único `SpawnLocation` en `BaseSpawn` (invisible, sin Decal, `Neutral = true`, `CanCollide = false`, `Anchored = true`).
- Determinista: semilla fija; cada sección usa su propio `Random` derivado.
- Secciones (variable `SECTION`, o `"All"`), en este orden:
  - `Terreno`: suelo, montañas, loma, garganta del río, montones de escombros y excavaciones de la mina y los sótanos;
  - `Caminos`;
  - `Base`;
  - `Ciudad`;
  - `Torre`;
  - `Mina`;
  - `Rio` (barrera);
  - `Puente` (roto, control militar y `MapVariants/PuenteConstruido`);
  - `Industrial` (incluye la línea eléctrica);
  - `Complejo`;
  - `BosqueAnomalo`;
  - `Bosque`;
  - `Marcadores`.
- Función exportada o sección auxiliar `PuenteConstruido` con `SECTION = "PuenteOn"` / `"PuenteOff"` para alternar la variante en Edit (misma lógica que el comando de debug).
- Comprobación final `summary(strict)` con los conteos de la sección 12.1, distancias de zona, superficie de marcadores (2 studs) y que ningún `PatrolPoint` quede en Y = 0 por un raycast fallido en zonas subterráneas.

### 12.1 Criterio de listo

Verificación con `search_game_tree` y por código:
- 7 `MapZone`; 12 `PieceSpawn` (3 por `PieceId`); 134 `ResourceSpawn` (68 Arbol, 42 Roca y 24 Arbusto); 13 `LootSpawn`; 4 `EnemySpawn`; 1 `Nest`; 6 `WaterZone`; 1 `BuildZone`; 4 `NoBuildZone`; 31 `PatrolPoint` en 5 rutas; 9 `Hideout`.
- Nuevos: 1 `BridgeSite`; 2 `BridgeEnd`; 6 `CreatureCrossing`; 4 `AnomalyZone`; 13 `LorePoint`; `PlayerBarrier` de X -720 a 720 con un solo hueco en el puente.
- Existen `BaseSpawn`, `RadioSocket`, `CampfireSocket`, `Map/Base/Radio` con sus 4 sockets, `Map/Puente` con `BridgeBuilt = false` y `ServerStorage/MapVariants/PuenteConstruido`.
- No existe `Workspace.Baseplate`; hay un único `SpawnLocation`.
- Ningún marcador a más de 2 studs de su superficie.
- Distancias de zona a la base dentro del 10 % de la sección 3.
- Con el puente roto no hay camino transitable de un territorio a otro (prueba manual en Play con el comando de debug apagado y encendido, fuera de esta tarea).
- Capturas sin huecos de terreno ni Parts flotando: base, ciudad, torre (y vista desde la cabina), mina por dentro, puente roto y construido, distrito (y vista desde la azotea), bosque anómalo, complejo en superficie y sótanos.

## Pendientes y fuera de esta spec

- Lighting, niebla y Atmosphere por zona (tarea aparte). El bosque anómalo y la mina lo necesitan para funcionar.
- Construcción del puente por tramos (Fase 3, construccion.md).
- IA: cruce a nado, trepada de la orilla norte, grupo de colisión de `PlayerBarrier`, restricción de acechadores al territorio con puente (F4).
- Efectos de `AnomalyZone` y propagación alrededor del puente.
- Textos y audio de los puntos de narrativa.
- Puertas interactuables.
