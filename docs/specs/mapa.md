# Mapa greybox — F1-1

Base: GDD §§1, 2, 3, 5; specs de objetivos, recolección e inventario, estímulos, construcción, ciclo de partida y arquitectura. Este documento es la guía para montar el greybox en Studio y el contrato de nombres que WorldService valida. Los valores que no vienen del GDD o de otra spec son **decisión de spec** y se ajustan en playtest. Las propuestas que cambian reglas de juego están marcadas **[pendiente de aprobar]**.

Lo que define este documento vive en Studio (`Workspace/Map`, `Workspace/Markers`) y no en Rojo. Los números que el código necesita (límites, conteos esperados, nombres de tags) van a `src/shared/config/WorldConfig.luau` y `ResourcesConfig.luau`, nunca hardcodeados.

---

## 0. Idea del mapa en una frase

Un claro con luz en el centro de un bosque oscuro, rodeado por cuatro lugares que se sienten distintos (metal, viento, agua, piedra) y que están más lejos cuanto más peligrosos son. Cada expedición es salir de la luz, entrar en un sitio con su propio sonido y volver antes de que el atardecer te alcance.

---

## 1. Tamaño, ejes y base

### Convención de coordenadas

- Unidades en studs. **Y hacia arriba.** **Norte = −Z**, **Este = +X** (norte es hacia donde mira la cámara por defecto en Studio).
- Origen `(0, 0, 0)` = centro del claro, a ras del suelo. El suelo del claro está en Y = 0.
- Todas las coordenadas de este documento son de greybox: posición del centro o del punto de apoyo en el suelo. Se pueden mover hasta ±10 studs para encajar con el terreno sin actualizar el documento. Si un cambio supera eso o altera una distancia del GDD en más de un 15 %, se actualiza aquí.

### Límites del mapa

| Dato | Valor | Dónde vive |
|---|---|---|
| Área jugable | X −640 a +360, Z −760 a +400 (1000 × 1160 studs) | `WorldConfig.Bounds` |
| Altura mínima válida | Y = −60 (por debajo, la pieza vuelve y el jugador se corrige) | `WorldConfig.Bounds.MinY` |
| Altura máxima válida | Y = +260 | `WorldConfig.Bounds.MaxY` |
| `Workspace.FallenPartsDestroyHeight` | −200 | Propiedad de Workspace, en Studio |

El límite físico son muros invisibles (`Map/Boundary`) detrás de bordes naturales que el jugador entiende sin texto: montaña al norte, barranco al este, bosque muy cerrado al oeste y al sur. La niebla esconde los muros. Ningún camino lleva directo a un muro invisible: cada sendero que se acerca al borde termina en algo que se lee como final (derrumbe, puente caído, pared de roca).

### Esquema (no a escala)

```
                                   NORTE (-Z)
 Z=-760 +------------------------------------------------------------+
        |              M O N T A Ñ A   (Terrain, no transitable)       |
 Z=-620 |                       interior MINA + NIDO (Parts)          |
        |                     [MINA] boca (90,-592)   derrumbe        |
        |                        |  patio de cantera  (180,-460)      |
        |                        |                       |            |
        |                Sendero Norte                   | Carretera  |
 Z=-300 | ~~~~~~~ arroyo ~~~~~~~ Paso del Arroyo ~~~~~~~~=+= puente   |
        |  [PANTANO]                |                    |            |
        | (-430,-130)               |                    |            |
        |  ~~~~~~~~ ---- Sendero del Pantano ---- (BASE 0,0) ----+----[GASOLINERA]
        |      \                                  /      |  (145,-40) |
        |       \ Atajo del Oeste    Sendero de la Colina  |            |
        |        \                    /                  |            |
 Z=+230 |          [TORRE] (-195,230) sobre la colina      |            |
        |                                         puente caído (180,400)
 Z=+400 +------------------------------------------------------------+
      X=-640                                                      X=+360
```

### La base: "El Claro"

| Elemento | Posición / tamaño | Notas |
|---|---|---|
| Claro | Círculo de radio 60 centrado en `(0, 0, 0)`, plano, Y = 0 | Terrain Grass. Pendiente 0°, cumple la cota única de BuildZone. |
| `BuildZones/Base` | Caja de 80 × 80 en planta, X −40 a +40, Z −40 a +40, alto 20 | Múltiplo de 8: 10 × 10 celdas de cimiento. Origen del grid en la esquina `(−40, 0, −40)`. |
| Caseta de radio | Planta 12 × 10, X −6 a +6, Z −11 a −1, alto 9 | Parts. **Una sola puerta** al sur (hueco de 5 × 7 centrado en X = 0, Z = −1) y dos ventanas con barrotes en los lados este y oeste: dejan ver y oír, no dejan pasar. |
| `RadioSocket` | `(0, 3, −9.5)`, mirando al sur | Radio fija contra la pared norte, dentro de la caseta. |
| `CampfireSocket` | `(0, 0, 9)` | Delante de la puerta de la caseta. |
| `BaseSpawn/01..04` | `(−6, 0, 16)`, `(6, 0, 16)`, `(−11, 0, 12)`, `(11, 0, 12)` | Alrededor de la fogata, mirando hacia ella. |
| Pilas de la base | `LootSpawns/Base/01` en `(−5, 3, −6)` y `/02` en `(−5, 3, −4)` | Dos lotes sueltos en una estantería de la pared oeste de la caseta (`PickupLoot`, sin contenedor). **Decisión de spec.** |
| `NoBuildZones` | Caseta + 2 studs de margen; pasillo de 6 × 10 delante de la puerta (X −3 a +3, Z −1 a +9); radio de 4 alrededor de cada spawn | La fogata ya protege su socket. El pasillo impide tapiar la única puerta. |
| Salidas del claro | Norte `(0, 0, −60)`, Este `(60, 0, −5)`, Suroeste `(−42, 0, 42)`, Oeste `(−60, 0, −8)` | Cuatro bocas de sendero. Son las cuatro direcciones de ataque (ver §5). |

**Por qué la fogata está en `(0, 0, 9)`.** La puerta de la caseta queda a 10 studs. Con los radios seguros de NightsConfig (12/10/8/6/0), la zona segura cubre la puerta en las noches 1 y 2 (en la 2 justo en el borde) y deja de cubrirla desde la noche 3. La radio está a 18.5 studs de la fogata, así que **nunca** está dentro de la zona segura: la defensa final se hace fuera de la luz protectora. El jugador siente que la base "se encoge" noche a noche sin que nadie se lo explique.

**Alrededor del claro.** Entre 60 y 150 studs hay bosque normal con los árboles y rocas más cercanos (ver §6). Talarlos abre el claro: hacia la noche 3 el grupo verá más lejos desde la base, pero también la verán desde más lejos. Es un cambio del paisaje que cuenta el paso del tiempo.

---

## 2. Las cuatro zonas

Distancia = de `(0, 0, 0)` al ancla de la zona (`Markers/Zones/<ZoneId>`, atributo `Anchor`), en planta. WorldService la compara con `ObjectivesConfig.Pieces[*].ApproxDistanceStuds` con tolerancia de ±15 %.

| ZoneId | Ancla | Distancia | Dirección | Volumen de zona (caja en planta) | Firma sensorial |
|---|---|---:|---|---|---|
| `Gasolinera` | `(145, 0, −40)` | 150 | Este | X 110 a 200, Z −90 a +40 | Metal, viento en un cartel, puertas que golpean |
| `Torre` | `(−195, 45, 230)` | 302 | Suroeste | X −290 a −120, Z +130 a +320 | Viento, madera que cruje, vista abierta |
| `Pantano` | `(−430, −6, −130)` | 449 | Oeste | X −560 a −320, Z −230 a −40 | Agua, ranas, niebla, tus propios pasos |
| `Mina` | `(90, 10, −592)` (boca) | 599 | Norte | X 30 a 170, Z −740 a −545, Y −40 a +40 | Goteo, eco, silencio, una respiración lejana |

El volumen de zona sirve para el revelado de la pieza (objetivos, F0-4), las estadísticas y el ambiente del cliente. Es más grande que la zona visible para que la pieza ya esté en `Workspace` antes de que se pueda ver.

### 2.1 Gasolinera (Batería): la zona tutorial

- **Forma:** explanada de asfalto de 70 × 50 junto a la carretera, Y 0 a 2. Bosque en tres lados, carretera al este.
- **Edificios (Parts):**
  - Tienda: 24 × 16, centro `(155, 0, −55)`, con trastienda al fondo.
  - Marquesina de surtidores: 20 × 10 en `(140, 0, −30)`.
  - Taller: 14 × 14 en `(170, 0, −25)`, con portón metálico.
  - Dos coches abandonados en la carretera: `(184, 0, −5)` y otro volcado en `(186, 0, 18)`.
- **Puertas de mapa:** tres puertas metálicas (tienda, trastienda y taller). Abrir y cerrar emite `MetalOpen` (30 studs).
- **Interiores oscuros:** sin ventanas o con cristales sucios. Aquí se aprende a usar la linterna de día y a oír cuánto ruido hace el metal.
- **Carretera cortada:**
  - Recta norte-sur en X = 180, de Z −460 a Z +400. Es la línea de visión más larga del mapa.
  - Al norte acaba en un derrumbe en `(180, 0, −460)`. Un paso estrecho entre rocas (6 studs) sigue hasta el patio de la mina: es la ruta alternativa a la mina.
  - Al sur acaba en un puente caído en `(180, 0, +400)`.

### 2.2 Torre (Antena): la colina abierta

- **Forma:** la colina "del Vigía", con base de radio 130 centrada en `(−190, 0, 230)` y cima pelada a Y = +45. Laderas de 15° a 25°, con la última pendiente al norte (hacia la base) de 30°.
- **Torre (Parts):**
  - Estructura de madera de 36 studs de alto y base de 10 × 10 en `(−195, 45, 230)`. La cabina del vigía está arriba, a Y +81.
  - La escalera es en zigzag con descansillos y peldaños de Parts, **no** `TrussPart`. Bajar con la Antena (manos ocupadas, sin correr) debe ser posible y lento.
  - Es el punto de referencia del mapa: sobresale de las copas (los árboles miden unos 30-40) y se ve desde el claro y desde todos los senderos de día.
- **Cabaña del guardabosques:** 10 × 8 en `(−250, 22, 150)`, en la ladera norte que baja hacia el pantano.
- **Línea de visión:** desde la cabina se ve el claro (el humo y la luz de la fogata), la gasolinera y el borde del pantano. Desde la base se ve la torre. **No hay dónde esconderse en la cima:** solo los escombros de una antena caída y unas pocas rocas.
- **De noche:** la niebla (45-120 studs) se traga la torre. La referencia que se usaba de día desaparece justo cuando más falta hace.

### 2.3 Pantano (Transceptor): ver poco y que cada paso suene

- **Forma:** cuenca irregular de unos 220 × 180, suelo de barro en Y −6 y agua de Terrain hasta Y −4.5 (1.5 studs de profundidad). Hay islas de tierra.
  - **El agua nunca supera 2 studs de profundidad.** Así el Humanoid camina y no entra en estado de nado.
  - Los volúmenes `WaterZones` cubren exactamente el agua transitable.
- **Campamento hundido (Parts):**
  - Cabaña mayor: 14 × 10, inclinada 6°, centro `(−440, −4, −125)`.
  - Cabaña pequeña al este: `(−410, −4, −140)`.
  - Cabaña de la isla al fondo: `(−505, −3, −95)`.
  - Un bote volcado: `(−385, −5, −175)`.
- **Pasarelas de madera (Parts):**
  - Unen la entrada del pantano `(−330, −4, −110)` con la cabaña mayor. Miden 4 de ancho y tienen dos tramos rotos.
  - Andar por la pasarela es silencioso, pero los tramos rotos obligan a bajar al agua (`WaterStep`, 25 studs).
  - **La cabaña de la isla no tiene pasarela.**
- **Niebla de día:** el cliente sube la densidad de Atmosphere al estar dentro del volumen `Pantano` (presentación, ver §9). Visibilidad objetivo de día: unos 40 studs.
- **Guaridas de los acechadores:** cuatro agujeros de barro en el borde oeste (ver §5). De día están vacíos y se ven como madrigueras: anuncian la noche 3 antes de que llegue.

### 2.4 Mina (Cristal): el nido

- **Exterior: patio de cantera (Terrain)**
  - Mide 80 × 60, centro `(100, 10, −555)`, de grava y pizarra al pie de la pared de la montaña.
  - Hay una caseta de capataz (Parts) en `(110, 10, −575)`, rieles y una vagoneta.
- **Boca:** en `(90, 10, −592)`, 10 de ancho y 12 de alto, enmarcada con vigas. Por dentro del interior de la montaña no entra luz exterior.
- **Interior (Parts, encerrado bajo Terrain de montaña):**

| Tramo | Desde → hasta | Tamaño del túnel | Notas |
|---|---|---|---|
| Túnel de entrada | `(90, 10, −592)` → `(90, −5, −640)` | 10 de ancho, 12 de alto, rampa de unos 17° | La luz del día se pierde a los 20 studs. |
| La Sala (cruce) | Centro `(90, −5, −640)`, 30 × 30, alto 16 | — | Cruce de tres galerías. Desde aquí se oye respirar al nido. |
| Galería de rieles (oeste) | `(75, −5, −640)` → `(45, −4, −655)` | 8 × 10 | Vagonetas, vigas caídas. |
| Sala de los cristales (este) | `(105, −5, −640)` → `(135, −8, −670)` | 10 × 12, termina en cámara de 20 × 20 | Vetas que brillan débilmente con la linterna (material Neon muy tenue, solo decorado). |
| Bajada al nido (norte) | `(90, −5, −655)` → `(95, −12, −688)` | 10 × 12 | Se estrecha a 8 al final. Huesos y arañazos. |
| Nido | Cámara de 50 × 24 × 36, centro `(90, −15, −708)` | — | Volumen `Nest`. |

- Todo túnel por el que pase la criatura mide **al menos 8 de ancho y 10 de alto**. Las medidas finales dependen del tamaño de `CriaturaPrincipal` (F4-1), que quizá obligue a ensancharlos.
- La mina no tiene ninguna luz propia. Con Lighting Future y el techo cerrado, el interior queda negro sin linterna. Hay que verificar que ninguna Part del techo tenga huecos por donde entre luz ambiente.

---

## 3. Puntos de aparición de las piezas

Tres marcadores por pieza en `Markers/ObjectiveSpawns/<PieceId>/01..03` (objetivos.md). Cada uno debe estar dentro del volumen de su zona y sobre una superficie accesible. Además debe haber al menos 4 studs libres alrededor (`WorldConfig.ProtectedRadiusStuds`) sin obstáculos que impidan el raycast de interacción.

En cada zona los tres puntos se ordenan de menos a más peligroso. El sorteo es uniforme: el grupo no sabe cuál le toca y la misma pieza puede ser fácil en una partida y difícil en otra.

| PieceId | Punto | Coordenadas | Lugar | Qué lo hace distinto |
|---|---|---|---|---|
| `Bateria` | 01 | `(172, 3, −24)` | Banco del taller | Interior oscuro tras un portón metálico: se aprende el ruido del metal. |
| `Bateria` | 02 | `(162, 3, −62)` | Trastienda de la tienda | La más profunda: hay que cruzar la tienda entre estanterías y abrir dos puertas metálicas. |
| `Bateria` | 03 | `(186, 2, 18)` | Maletero del coche volcado | Fuera, en la carretera, visible desde lejos. Fácil de día y muy expuesta si se recoge al atardecer. |
| `Antena` | 01 | `(−178, 46, 244)` | Escombros al pie de la torre | Sin escalera, pero en la cima pelada, sin cobertura. |
| `Antena` | 02 | `(−195, 82, 230)` | Cabina del vigía | 36 studs de escalera de bajada con la pieza pesada. |
| `Antena` | 03 | `(−250, 22, 150)` | Cabaña del guardabosques | Fuera del sendero principal, en la ladera que baja al pantano: cerca de los acechadores desde la noche 3. |
| `Transceptor` | 01 | `(−385, −5, −175)` | Bote volcado | En el borde, pero dentro del agua: se llega sin pasarela y haciendo ruido. |
| `Transceptor` | 02 | `(−440, −4, −125)` | Cabaña mayor | En el centro del campamento, por pasarela con un tramo roto. |
| `Transceptor` | 03 | `(−505, −3, −95)` | Cabaña de la isla | La más lejana, toda por agua y junto a las guaridas de los acechadores. |
| `Cristal` | 01 | `(55, −3, −648)` | Galería de rieles | La más cercana a la salida, unos 60 studs dentro. |
| `Cristal` | 02 | `(132, −7, −668)` | Sala de los cristales | Unos 90 studs dentro. Hay que elegir bien qué veta alumbrar. |
| `Cristal` | 03 | `(100, −12, −688)` | Antesala del nido | A 2 studs del volumen `Nest`. La linterna encendida aquí es la peor decisión del juego, y apagada no se ve nada. |

Distancias en planta al origen: Batería entre 173 y 187, Antena entre 292 y 302, Transceptor entre 423 y 514, Cristal entre 650 y 695. Los tres puntos del Cristal quedan por encima de los 600 del GDD porque están dentro de la montaña. La distancia del GDD se mide a la boca de la mina, que es el ancla de la zona, y la tolerancia de ±15 % se aplica a las anclas, no a cada punto.

---

## 4. Caminos, referencias, visión, cuellos de botella y escondites

### Senderos

Los senderos son Terrain de material `Ground` o `Mud`, de 8 a 10 studs de ancho, con el borde marcado por arbustos bajos. Nadie los obliga a seguirse, pero el bosque fuera de ellos es más denso, más lento de leer y más oscuro.

| Sendero | Recorrido (puntos de paso) | Largo aprox. | Caminando (12/s) | Cargando pesado (8/s) |
|---|---|---:|---:|---:|
| Sendero del Este | Base `(60, 0, −5)` → `(120, 0, −25)` → carretera | 170 | 14 s | — |
| Sendero de la Colina | `(−42, 0, 42)` → `(−110, 10, 130)` → `(−160, 30, 190)` (zigzag) → torre | 340 | 28 s | 43 s |
| Sendero del Pantano | `(−60, 0, −8)` → `(−200, −1, −50)` → `(−300, −3, −95)` → pasarela | 490 | 41 s | — |
| Sendero Norte | `(0, 0, −60)` → `(20, 2, −200)` → Paso del Arroyo `(50, 0, −300)` → `(80, 8, −480)` → boca de la mina | 650 | 54 s | — |
| Ruta del derrumbe | Carretera hasta `(180, 0, −460)` → paso entre rocas → patio de la mina | 720 desde la base | 60 s | — |
| Atajo del Oeste | Cabaña del guardabosques `(−250, 22, 150)` → `(−330, 0, 40)` → borde sur del pantano | 230 | 19 s | 29 s |

Los tiempos incluyen un factor de rodeo de 1.15 sobre la línea recta. Son de una sola ida y sin contar la búsqueda dentro de la zona.

**Regla de diseño del atardecer:**
- El atardecer dura 45 s. Caminando se recorren 540 studs.
- Desde todas las zonas menos la mina se llega a la base caminando dentro del atardecer, aunque con la Antena (43 s) se llega justo.
- **Desde la mina no**: hay que salir antes de que empiece el atardecer, o correr y gastar estamina, o pasar la noche fuera.
- Así la mina es la expedición que se planea al principio del día, y las demás son las que "da tiempo de hacer una más".

### Puntos de referencia

| Referencia | Visible desde | De noche |
|---|---|---|
| La torre | Todo el mapa por encima de las copas | Se pierde en la niebla |
| Humo de la fogata | Colina, carretera y Sendero Norte hasta el arroyo | La luz de la fogata se ve unos 40 studs (`Campfire.VisualRange`) |
| Pared de la montaña | Todo el norte del mapa | Silueta negra contra el cielo |
| Cartel de la gasolinera (alto, en un poste de 20 studs) | Carretera y Sendero del Este | No |
| Marcas de sendero: cintas reflectantes en troncos, cada 25 studs | Solo de cerca | **Brillan con la linterna** a unos 30 studs. Es la forma de volver de noche. |

Las cintas reflectantes son decorado del cliente: una Part de `Neon` muy oscuro o una `SurfaceGui` que solo se ve iluminada. No son estímulos de luz ni pasan por el servidor. Hacen que la linterna, que atrae a la criatura, sea también la forma de no perderse.

### Líneas de visión

- **Claro:** es un cuenco abierto de 120 de diámetro. Desde el borde del bosque se ve todo el claro iluminado; desde el claro, el bosque a 30 studs ya es negro. Quien está en la base es visible y no ve. Es intencional.
- **Carretera:** es la vista más larga del mapa (860 studs en línea recta). De día se ve venir todo y se te ve desde lejos. Aquí va un avistamiento diurno (§5).
- **Colina:** de 360° desde la cima. La ladera norte es abierta y no tiene árboles en los últimos 80 studs.
- **Pantano:** la visibilidad la fija la niebla, no la geometría. Los troncos muertos y las cabañas tapan aún más.
- **Mina:** no hay líneas largas. La Sala es el único espacio con más de 20 studs de visión.

### Cuellos de botella

| Lugar | Posición | Ancho | Por qué importa |
|---|---|---:|---|
| Paso del Arroyo | `(50, 0, −300)` | Tronco de 4 | Única forma de cruzar el arroyo en silencio. Si no, se vadea con `WaterStep`. Cruce en fila de uno. |
| Puente de la carretera | `(180, 0, −330)` | 12 | Cruce rápido del arroyo por la ruta larga. |
| Paso del derrumbe | `(180, 0, −460)` | 6 | Rocas a ambos lados y sin salida lateral. |
| Boca de la mina | `(90, 10, −592)` | 10 | Única entrada y única salida de la mina. |
| Bajada al nido | `(95, −12, −688)` | 8 | El último estrechamiento antes del nido. |
| Pasarelas del pantano | `(−330, −4, −110)` a `(−440, −4, −125)` | 4 | Silenciosas pero estrechas y rotas. |
| Escalera de la torre | `(−195, 45..81, 230)` | 3 | Lenta, sin salida lateral, a la vista desde toda la colina. |
| Puerta de la caseta | `(0, 0, −1)` | 5 | La única entrada a la radio. Es el punto de la defensa final. |

### Escondites

El GDD pide que quedarse quieto, a oscuras y en silencio permita sobrevivir al nivel 2-3 de la escalera de avisos. Para eso el mapa necesita sitios donde la linterna y la línea de visión de la criatura queden cortadas. Todo escondite es geometría opaca con `CanQuery = true`, que corta el raycast de percepción. No hay mecánica de "entrar a esconderse".

| Zona | Escondites |
|---|---|
| Bosque | Troncos caídos de 2 studs de alto, rocas grandes y raíces de árboles volcados. Al menos uno cada 40 studs a lo largo de cada sendero. |
| Gasolinera | Detrás del mostrador, entre estanterías y detrás de los coches. |
| Colina | Casi ninguno a propósito: dos rocas en la ladera y los escombros de la antena. |
| Pantano | Dentro de las cabañas y detrás de troncos muertos. |
| Mina | Huecos laterales de 3 × 3 en las galerías (uno por galería) y detrás de las vagonetas. |
| Base | Dentro de la caseta, detrás de lo que el grupo construya. |

**Arbustos densos [pendiente de aprobar].** Propuesta: los arbustos altos (`Map/Forest/Bushes`) tienen `CanCollide = false` y `CanQuery = true`. El jugador los atraviesa y el Pathfinding de la IA no los trata como muro, pero cortan el raycast de linterna y visión. Un jugador agachado dentro de un arbusto es invisible a la luz, aunque no al ruido. Da al jugador una forma clara y legible de esconderse sin añadir código nuevo. A cambio, cambia la percepción: F4-2 tiene que contar con ella y las pruebas de linterna de `estimulos.md` también. Si no se aprueba, los arbustos llevan `CanQuery = false` y son solo decorado.

---

## 5. Enemigos: aparición, patrulla y aproximación

Este mapa solo pone los marcadores. Cómo y cuándo se usan (estados de la IA, umbrales, velocidades) lo deciden F4-1 y F4-2. Los nombres siguientes son el contrato para que AIService los encuentre.

### Criatura principal

| Marcador | Posición | Uso |
|---|---|---|
| `EnemySpawns/Main/Nido` | `(90, −15, −708)` | Donde duerme de día. Lugar de retorno al amanecer. |
| `EnemySpawns/Main/Noche_01` | `(−40, 3, −170)` | Detrás de la loma al norte del claro. |
| `EnemySpawns/Main/Noche_02` | `(175, 0, −190)` | Bosque junto a la carretera, al este. |
| `EnemySpawns/Main/Noche_03` | `(−150, 5, 40)` | Bosque entre la base y la colina. |

**Decisión de spec:** al empezar la noche, la criatura aparece en el punto `Noche_*` sin línea de visión a ningún jugador y más lejano a todos. Así no tiene que recorrer los 650 studs desde el nido en cada noche. Los tres puntos están entre 150 y 200 studs de la base: la primera señal de cada noche (el silencio, el llamado lejano) llega desde una dirección distinta.

**Patrullas (`PatrolPoints/Main/<Ruta>/NN`):**

| Ruta | Puntos | Uso propuesto |
|---|---|---|
| `Ronda` | 8 puntos en anillo de radio 80 alrededor de la base: `(0, 0, −80)`, `(57, 0, −57)`, `(80, 0, 0)`, `(57, 0, 57)`, `(0, 0, 80)`, `(−57, 0, 57)`, `(−80, 0, 0)`, `(−57, 0, −57)` | Noche 1 ("solo ronda") y fases BuildUp. Pasa justo por el borde de la luz del claro. |
| `Bosque` | 10 puntos: Sendero Norte `(20, 2, −200)`, Paso del Arroyo `(50, 0, −300)`, carretera `(180, 0, −150)`, `(180, 0, 60)`, gasolinera `(140, 0, 20)`, pie de colina `(−100, 8, 150)`, Atajo del Oeste `(−330, 0, 40)`, borde del pantano `(−300, −3, −60)`, Sendero del Pantano `(−200, −1, −50)`, loma norte `(−40, 3, −170)` | Caza por el bosque cuando hay jugadores fuera. |
| `Mina` | 5 puntos: nido, bajada, La Sala, túnel de entrada `(90, 2, −615)`, patio `(100, 10, −555)` | Despertar diurno (F4) y vuelta al nido. |

**Aproximaciones a la base (`PatrolPoints/Base/<Dir>`, atributo `Role = "SiegeStart"`):**

| Dir | Posición | Llega por |
|---|---|---|
| `N` | `(0, 0, −95)` | Sendero Norte |
| `E` | `(95, 0, −10)` | Sendero del Este |
| `SW` | `(−70, 0, 70)` | Sendero de la Colina |
| `W` | `(−95, 0, −10)` | Sendero del Pantano |

Todos están fuera de la `BuildZone`, para que el grupo no construya encima del punto donde empieza un asedio. Desde la noche 3, la combinación natural es **criatura por N o E, acechadores por W o SW**: "los ataques llegan desde dos lados a la vez" sale de la geografía.

### Acechadores menores

| Marcador | Posición | Notas |
|---|---|---|
| `EnemySpawns/Stalker/01` | `(−520, −6, −180)` | Guarida en el barro del borde oeste del pantano. |
| `EnemySpawns/Stalker/02` | `(−480, −6, −60)` | Igual. |
| `EnemySpawns/Stalker/03` | `(−400, −6, −215)` | Igual. |
| `EnemySpawns/Stalker/04` | `(−540, −6, −120)` | Igual. |

`PatrolPoints/Stalker/Pantano/01..06` es un bucle entre las cabañas. `PatrolPoints/Stalker/Claro/01..05` sigue el Sendero del Pantano hasta `W`, con un desvío al `SW` por el Atajo del Oeste. Los acechadores tardan más en llegar a la base que la criatura (unos 490 studs). La primera ola de la noche 3 llega, por tanto, con unos segundos de retraso respecto a la criatura.

### Rastros y avistamientos diurnos

Esto sale de `ciclo-partida.md`: rastros desde el día 3 y avistamiento desde el día 4. Los rastros se acercan cada día; eso cuenta que la criatura "se acerca" sin una sola línea de texto.

| Marcador | Atributo `MinDay` | Posición aproximada | Qué es |
|---|---:|---|---|
| `DayTraces/01..03` | 3 | A unos 150 studs de la base, uno en el Sendero Norte, otro en el del Este y otro en el del Pantano | Arañazos en troncos, huellas en el barro |
| `DayTraces/04..06` | 4 | A unos 100 studs, en los senderos de la Colina, Norte y Este | Árbol partido, animal muerto |
| `DayTraces/07..09` | 5 | A 65-70 studs, en el borde del claro, en tres de las cuatro salidas | Huellas que dan la vuelta a la base |
| `DaySightings/01` | 4 | `(180, 0, −260)`, al fondo de la carretera | Se ve desde la gasolinera |
| `DaySightings/02` | 4 | `(−150, 12, 110)`, entre los árboles de la ladera | Se ve desde la colina mirando hacia la base |
| `DaySightings/03` | 4 | `(−300, −2, −40)`, en el borde del pantano | Silueta en la niebla |
| `DaySightings/04` | 4 | `(10, 15, −140)`, en la loma norte | Se ve desde el claro |

Cada avistamiento debe estar a 80-140 studs de un lugar donde suela haber jugadores y tener línea de visión a ese lugar. No debe ser alcanzable rápido desde ahí: entre medias hay agua, pendiente o un barranco. La criatura se ve y no ataca (ciclo-partida).

---

## 6. Árboles y rocas recolectables

Los nodos se clonan desde los prefabs `Arbol` y `Roca` en cada marcador de `Markers/ResourceSpawns` al empezar la run, y no se regeneran (recolección). El bosque decorativo es otra cosa: troncos y copas en `Map/Forest`, sin tag ni HP, que dan densidad y escondites.

### Presupuesto

Con un factor de producción ×1.0, un árbol da 10 Madera y una roca 12 Piedra. Estimación para 4 jugadores en una run completa:
- **Madera:** unos 400 en total. Herramientas, unos 30 de fogata y combustible (alrededor de 120 si la fogata nunca se apaga), unas 20 paredes, unos 12 cimientos, reparaciones y vendas.
- **Piedra:** unos 120.

El mapa da unas 1.7 veces la madera necesaria (68 árboles, 680 Madera) y unas 2.6 veces la piedra (26 rocas, 312 Piedra). Hay margen para errores, pero no para gastar sin pensar.

**Decisión de spec:** las cantidades por anillo están pensadas para que la base se quede sin árboles cercanos hacia la noche 3. A partir de ahí recolectar obliga a alejarse, y la avaricia contra la seguridad crece con la partida.

| Zona (`ZoneId` del nodo) | Árboles | Rocas | Distribución |
|---|---:|---:|---|
| `Base` (anillo 60-150 alrededor del claro) | 20 | 5 | Repartidos en los cuatro cuadrantes. Ninguno dentro del claro (r < 60). |
| `Bosque` (senderos y entre zonas) | 20 | 4 | En grupos de 3 a 5 junto a los senderos, a 6-20 studs del centro del sendero. |
| `Gasolinera` | 6 | 2 | En el borde del bosque que rodea la explanada. |
| `Torre` | 6 | 6 | Árboles solo en las laderas bajas. Rocas en la cima y la ladera: la colina es la cantera "segura". |
| `Pantano` | 10 | 1 | Árboles muertos (mismo prefab, otro color en el greybox). Hay que talar con los pies en el agua. |
| `Mina` exterior (patio) | 6 | 5 | Patio de cantera. |
| `Mina` interior | 0 | 3 | En La Sala y la galería de rieles. Es la mejor piedra del mapa y picarla hace 50 studs de ruido a 60-80 del nido. |
| **Total** | **68** | **26** | |

**Reglas de colocación:**
- Hay al menos 6 studs entre troncos de nodos.
- Ningún nodo queda a menos de 6 studs del centro de un sendero, de modo que un árbol nunca tapa el camino.
- Ningún nodo queda dentro de una `BuildZone`, un `NoBuildZone` o a menos de 4 studs de un spawn de pieza o de un contenedor.
- Cada marcador tiene atributos `Id` (único, p. ej. `Arbol_Base_07`), `NodeKind` (`Arbol` o `Roca`) y `ZoneId`.
- WorldService compara los conteos por zona con `ResourcesConfig.NodeCounts`, igual que `ZoneLoot`: si no coinciden, la run no arranca.

**Contenedores** (`Markers/LootSpawns/<ZoneId>/01..03`, recolección: 1 Pila y 2 Chatarra cada uno):

| Zona | 01 | 02 | 03 |
|---|---|---|---|
| Gasolinera (`MetalOpen` al abrir) | Caja de herramientas del taller `(168, 1, −20)` | Almacén de la tienda `(150, 1, −58)` | Maletero del coche `(184, 1, −5)` |
| Torre | Caja de suministros al pie de la torre `(−200, 45, 222)` | Cofre de la cabina del vigía `(−192, 81, 232)` | Cabaña del guardabosques `(−246, 22, 154)` |
| Pantano | Cabaña pequeña este `(−410, −4, −140)` | Cabaña mayor `(−446, −4, −120)` | Cabaña de la isla `(−500, −3, −100)` |
| Mina | Caseta del capataz `(110, 10, −575)` | Galería de rieles `(60, −4, −640)` | Sala de los cristales `(125, −7, −672)` |

En cada zona el contenedor más cercano a la pieza más peligrosa es también el que está más adentro. Ir a por todo el botín de una zona lleva al mismo sitio peligroso que la pieza difícil.

---

## 7. Terrain y Parts

| Va con **Terrain** | Va con **Parts** |
|---|---|
| Todo el suelo jugable: `Grass` en el claro y los prados, `LeafyGrass` en el bosque, `Ground` y `Mud` en los senderos | Caseta de radio y radio |
| Colina del Vigía (`Grass` y `Rock` en la cima) | Torre del vigía, escalera, cabaña del guardabosques |
| Montaña del norte (`Rock` y `Slate`, pendientes de más de 60°, no transitable) | Interior completo de la mina: túneles, La Sala, galerías, nido |
| Patio de la cantera (`Slate` y `Pebble`) | Marco de la boca de la mina y caseta del capataz |
| Pantano: `Mud` + agua de Terrain de 1.5 de profundidad + islas de `Ground` | Cabañas del pantano, pasarelas, bote |
| Arroyo (agua de 1.5) y sus orillas | Gasolinera: tienda, taller, marquesina, coches, cartel, puertas metálicas |
| Carretera (`Asphalt`, con grietas de `Ground`) | Tronco del Paso del Arroyo, puente de la carretera, derrumbe (rocas grandes en Parts para controlar la colisión exacta) |
| Barranco del este y bosque cerrado del oeste y sur | Bosque decorativo (greybox: cilindro + esfera; luego MeshParts) |
| | Muros invisibles del límite |
| | Todos los marcadores y volúmenes de `Workspace/Markers` |

**Por qué la mina va con Parts y no con cuevas de Terrain:**
- Los raycasts de interacción y linterna contra Parts son predecibles.
- Los túneles se pueden ajustar al tamaño de la criatura con números exactos.
- Es fácil garantizar que no entre luz.

La montaña de Terrain tapa la mina por arriba con al menos 20 studs de espesor.

**Límites de rendimiento (greybox):**
- Bosque decorativo: como máximo 1500 árboles de 3 Parts como mucho cada uno.
- `CastShadow = false` en las copas lejanas, a criterio de Mario tras medir.
- Todo el `Map` va anclado.

**StreamingEnabled [pendiente de aprobar].** Con este tamaño de mapa y este bosque, recomiendo `Workspace.StreamingEnabled = true` con `StreamingTargetRadius` de 512 y `ModelStreamingMode = Persistent` para la torre y el claro. La niebla nocturna ya oculta todo más allá de 120 studs, así que no se nota. Implica que el código de cliente nunca asuma que una Part lejana de `Map` existe y use `WaitForChild` o eventos. El servidor no se ve afectado. Hay que decidirlo antes de F2, porque cambia cómo se escriben los controllers.

---

## 8. Nombres, carpetas y tags

### Principio

- **Carpeta = dónde está. Tag = qué es. Atributos = sus datos.**
- WorldService encuentra cada cosa por su ruta de carpeta (arquitectura.md) y comprueba que tenga el tag y los atributos esperados.
- Si algo está en la carpeta sin el tag, o tiene el tag fuera de su carpeta, `ValidateStudio` falla con la ruta exacta y la run no arranca. No se generan sustitutos.
- Los tags y atributos se ponen en Studio (Tag Editor o el panel de Properties), nunca por código en runtime.
- Los nombres de tags viven en `WorldConfig.Tags`. El código nunca escribe el texto del tag directamente.

### Árbol de Workspace

```
Workspace
  Terrain                              (suelo, colina, montaña, agua; §7)
  Map                                  (arte estático; Rojo no lo toca)
    Base
      Caseta                           (Model; Radio dentro, fija e indestructible)
      Decor
    Zones
      Gasolinera
        Geometry
        Doors/<NN>                     (tag MapDoor)
        Containers/<NN>                (visual del contenedor LootSpawns/Gasolinera/<NN>)
      Torre/  Pantano/  Mina/          (misma estructura)
    Forest
      Trees                            (decorativos, sin tag)
      Bushes                           (ver §4)
      TrailMarkers                     (cintas reflectantes, decoración de cliente)
    Paths                              (troncos, puentes, señales)
    Boundary                           (muros invisibles)
    Ambience                           (volúmenes de ambiente de cliente, tag AmbientZone)
  Markers                              (invisibles, sin colisión; la autoridad lee de aquí)
    BaseSpawn/01..04
    RadioSocket
    CampfireSocket
    ObjectiveSpawns/<PieceId>/01..03
    ResourceSpawns/<ZoneId>/<Id>
    LootSpawns/<ZoneId>/<NN>           (ZoneId incluye Base)
    EnemySpawns/Main/{Nido, Noche_01..03}
    EnemySpawns/Stalker/01..04
    PatrolPoints/Main/<Ruta>/<NN>
    PatrolPoints/Stalker/<Ruta>/<NN>
    PatrolPoints/Base/{N, E, SW, W}
    Zones/<ZoneId>                     (volumen de zona con atributo Anchor)
    Nest
    WaterZones/<NN>
    BuildZones/Base
    NoBuildZones/<NN>
    InvalidPieceZones/<NN>             (volúmenes donde una pieza no puede quedar: pozos, montaña)
    DayTraces/<NN>
    DaySightings/<NN>
  Runtime                              (lo crea el servidor; clones de cada run)
```

Respecto a `arquitectura.md` y `WorldConfig.MarkerNames`, son **nuevos**: `PatrolPoints`, `Zones`, `InvalidPieceZones`, `DayTraces` y `DaySightings`. Además, `BaseSpawn` pasa de marcador único a carpeta con cuatro puntos. `Zones` sustituye a los "volúmenes de zonas" que arquitectura situaba en `Map`. Así todo lo que la autoridad lee está en `Markers`.

### Propiedades comunes de marcadores y volúmenes

- Son Parts con `Anchored = true`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`, `Transparency = 1` y `CastShadow = false`.
- Un raycast de interacción o de luz nunca choca con un marcador.
- La pertenencia a un volumen la resuelve el servidor con `GetPartBoundsInBox` (o con una comprobación de punto en caja) usando el `CFrame` y el `Size` del volumen. Nunca se usa `Touched` (F0-4).
- Para ver los marcadores mientras se construye en Studio, se usa un plugin o se cambia `Transparency` en local. Antes de publicar el place, todo queda en 1.

### Tags de CollectionService

| Tag | Dónde | Atributos obligatorios | Lo lee |
|---|---|---|---|
| `PlayerSpawn` | `BaseSpawn/*` | `Id` | PlayerService |
| `RadioSocket` | `RadioSocket` | `Id` | ObjectiveService |
| `CampfireSocket` | `CampfireSocket` | `Id` | BuildingService |
| `PieceSpawn` | `ObjectiveSpawns/*/*` | `Id`, `PieceId`, `SpawnIndex` (1 a 3) | ObjectiveService |
| `ResourceNode` | `ResourceSpawns/*/*` | `Id`, `NodeKind`, `ZoneId` | ResourceService |
| `LootSpawn` | `LootSpawns/*/*` | `Id`, `ZoneId`, `LootMode` (`Container` o `Loose`), `OpenNoise` (`None` o `MetalOpen`) | ResourceService |
| `LootContainerVisual` | `Map/Zones/*/Containers/*` | `ContainerId` (= `Id` de su `LootSpawn`). Hijos `Closed` y `Open` | ResourceService (cambia la pose) |
| `MapDoor` | `Map/Zones/*/Doors/*` | `Id`, `DoorMaterial` (`Metal` o `Wood`). Hijo `Hoja` y Attachments `PoseClosed` y `PoseOpen` | BuildingService (mismas reglas que MarcoPuerta) |
| `EnemySpawn` | `EnemySpawns/*/*` | `Id`, `Agent` (`Main` o `Stalker`), `Role` (`Nest`, `Night` o `Den`) | AIService |
| `PatrolPoint` | `PatrolPoints/*/*/*` | `Id`, `Agent` (`Main`, `Stalker` o `Any`), `Route`, `Order`, `Role` (`Patrol` o `SiegeStart`), `WaitSeconds` opcional | AIService |
| `ZoneVolume` | `Zones/*` | `ZoneId`, `Anchor` (Vector3) | WorldService, ObjectiveService (revelado), estadísticas |
| `NestVolume` | `Nest` | `Id` | StimulusService, AIService |
| `WaterZone` | `WaterZones/*` | `Id` | PlayerService y StimulusService (`WaterStep`) |
| `BuildZone` | `BuildZones/*` | `Id`, `GridOrigin` (Vector3) | BuildingService |
| `NoBuildZone` | `NoBuildZones/*` | `Id`, `Reason` | BuildingService |
| `InvalidPieceZone` | `InvalidPieceZones/*` | `Id` | ObjectiveService (watchdog) |
| `DayTrace` | `DayTraces/*` | `Id`, `MinDay` | DayNightService y presentación |
| `DaySighting` | `DaySightings/*` | `Id`, `MinDay`, `LookFrom` (Vector3) | DayNightService y AIService |
| `AmbientZone` | `Map/Ambience/*` | `AmbienceId`, `Priority` | Solo cliente (audio y niebla local) |
| `ScareSpot` | `Map/Ambience/*` | `CueId`, `CooldownSeconds` | Solo cliente; ver §9 |

**Seguridad.** Todo lo que está en `Workspace` replica a los clientes. Que un cliente lea los tres puntos posibles de cada pieza, los contenedores o los puntos de patrulla no se considera fuga: son públicos o se aprenden jugando. Lo que sí sería fuga (qué punto salió elegido y qué hay dentro de un contenedor cerrado) ya lo resuelve `objetivos.md` y `recoleccion-inventario.md` (F0-4), porque esas instancias no existen en `Workspace` hasta que toca. Riesgo aceptado: un exploit puede dibujar las rutas de patrulla. Si en playtest se demuestra que importa, se moverían `EnemySpawns` y `PatrolPoints` a `ServerStorage` **[pendiente de aprobar si hiciera falta]**.

### Validaciones de `WorldService.ValidateStudio`

Con cualquier fallo, la run no arranca y se registra la ruta exacta.

1. Existen `Map`, `Markers` y todas las subcarpetas de `WorldConfig.MarkerNames`.
2. Hay exactamente 3 `PieceSpawn` por pieza, cada uno dentro del `ZoneVolume` de su zona. La distancia de cada ancla al origen está dentro de ±15 % de `ApproxDistanceStuds`.
3. Los conteos de `ResourceNode` por zona coinciden con `ResourcesConfig.NodeCounts`. Los de `LootSpawn` coinciden con `ZoneLoot`, y cada contenedor tiene su `LootContainerVisual`.
4. Todos los `Id` son únicos en todo `Markers` y `Map`.
5. Cada tag está en su carpeta y tiene sus atributos, con el tipo correcto.
6. `BuildZones/Base` es múltiplo de 8 en X y Z y está en terreno plano (raycasts en sus esquinas y su centro con una diferencia de Y de 0.25 o menos).
7. Ningún `PieceSpawn`, `LootSpawn` ni `PlayerSpawn` está dentro de un `InvalidPieceZone`, del `Nest` ni de un `WaterZone` más profundo de 2 studs.
8. `RadioSocket` y `CampfireSocket` están dentro de `BuildZones/Base`, y el `NoBuildZone` del pasillo de la caseta existe.
9. Hay al menos un `PatrolPoint` con `Role = "SiegeStart"` por cada salida del claro.

---

## 9. Diseño de terror: dónde va la tensión

### Ritmo de una expedición

Cada viaje tiene la misma forma:

1. Salir de la luz: el claro abierto y el humo de la fogata.
2. Recorrer el bosque, que es neutral: hay oclusión, sonidos normales y cintas reflectantes.
3. Cruzar un **umbral**, un cambio claro de sonido y luz al entrar en la zona.
4. Llegar al **punto peligroso**: la pieza, el contenedor del fondo.
5. Hacer la decisión de vuelta, con el reloj en contra.

Los umbrales están hechos con geometría, no con texto:

| Zona | Umbral |
|---|---|
| Gasolinera | El bosque se abre de golpe a asfalto y el viento suena en metal. |
| Torre | Se acaban los árboles: la ladera abierta es un umbral de exposición. |
| Pantano | El suelo baja a barro y aparecen la niebla y las ranas. |
| Mina | Cruzar la boca: pasar de luz a negro absoluto en 20 studs. |

### Respiros

No toda zona es un pico:
- La bajada de la colina hacia el claro, con el humo de la fogata a la vista, es un respiro visual.
- El patio de la cantera, antes de entrar en la mina, es un momento de calma deliberado: sitio abierto, piedra que recoger, la boca negra delante.
- Que haya calma justo antes del peor momento hace que el peor momento pese más.

### Oscuridad

- En el mapa no hay más luces que la fogata y las linternas. Nada de farolas, lámparas ni neones encendidos en la gasolinera. Si hace falta un detalle de luz (una brasa, el panel de la radio), es tenue y no se confunde con una linterna.
- Los interiores (tienda, taller, cabañas, cabina del vigía, mina) son oscuros incluso de día. La linterna se usa de día desde el día 1, así se aprende a gestionar la batería antes de que importe.
- La mina es la única oscuridad total y es también el nido. Es el sitio donde la regla "la luz te delata" se juega con más cosas en contra.

### Sonido: qué va en cada sitio

| Lugar | Ambiente de día | Ambiente de noche | Detalle |
|---|---|---|---|
| Claro | Pájaros, viento suave, fogata | Grillos, fogata | La fogata baja suena distinto (GDD). |
| Bosque | Pájaros, hojas | Grillos, búhos lejanos | Los insectos son la base que el silencio de nivel 0 corta: tiene que haberlos siempre para que su ausencia se note. |
| Gasolinera | Viento, cartel que chirría, una puerta suelta que golpea a intervalos | Igual, más bajo | La puerta que golpea es decorado: **nunca** se parece al golpe de la criatura contra una pared. |
| Colina y torre | Viento fuerte, madera que cruje | Viento | Arriba no se oye el bosque. El silencio de nivel 0 aquí no sirve de aviso, y por eso la colina da miedo de otra forma. |
| Pantano | Ranas fuertes, agua, insectos | Ranas | Cuando las ranas callan, es el aviso de nivel 0 más claro del mapa. Los pasos propios en el agua van con volumen alto a propósito. |
| Mina | Goteo, eco de los pasos, zumbido grave | Igual | Desde La Sala se oye una respiración lenta que viene del nido (audio 3D en `Nest`). Es la criatura dormida y real, no un efecto. Cuanto más alta suena, más cerca estás. |

### Regla de oro de los sustos de ambiente

Los `ScareSpot` (ramas que crujen, un objeto que cae en la gasolinera, un pájaro que sale volando) son cosméticos, solo de cliente, y existen para mantener la tensión de día. **Nunca usan los sonidos de la escalera de avisos de la criatura**: el llamado, los pasos pesados, la respiración, el parpadeo de linterna ni el silencio súbito del ambiente.

El GDD promete que la criatura siempre avisa. Si el jugador aprende que esas señales a veces son falsas, deja de creerlas y la escalera pierde todo su valor.

Además, los `ScareSpot`:
- no generan estímulo de IA;
- tienen un cooldown por jugador;
- no se activan de noche, porque de noche la tensión ya la pone la criatura.

### Momentos diseñados en el mapa

| Momento | Dónde | Qué lo produce |
|---|---|---|
| Primer vistazo de la criatura | Loma norte `(10, 15, −140)` desde el claro (día 4) | Avistamiento a la vista desde la base: ya no es seguro ni de día. |
| Carrera del atardecer con la Antena | Ladera norte de la colina | 43 s de camino a velocidad reducida, sin cobertura, viendo la luz cambiar. |
| Cruzar el arroyo de noche | Paso del Arroyo | O fila de uno sobre un tronco o 25 studs de ruido en el agua. |
| La linterna en la antesala | Cristal 03 | La pieza está a 2 studs del nido. |
| Las ranas se callan | Pantano | Aviso de nivel 0 en el sitio con menos visibilidad. |
| Los rastros que se acercan | Bordes del claro, días 3-5 | Cada mañana están más cerca. |
| La puerta de la caseta | Defensa final | Una sola puerta, la radio fuera de la zona segura, ventanas con barrotes para ver lo que viene. |

---

## 10. Cambios que este documento implica en otros archivos

No los aplico: este encargo solo crea este archivo. Quedan para F1-1 en Studio y para quien implemente WorldService.

- `WorldConfig.luau`:
  - `Bounds`, `Tags` (los nombres de §8) y `ZoneIds` (`Base`, `Bosque`, `Gasolinera`, `Torre`, `Pantano`, `Mina`).
  - Añadir a `MarkerNames`: `PatrolPoints`, `Zones`, `InvalidPieceZones`, `DayTraces`, `DaySightings`.
  - `ZoneDistanceTolerance = 0.15`.
- `ResourcesConfig.luau`: `NodeCounts` por zona (tabla de §6).
- `arquitectura.md`:
  - Actualizar la lista de `Workspace/Markers` (nuevas carpetas y `BaseSpawn` como carpeta con 4 puntos).
  - Mover los volúmenes de zona de `Map` a `Markers/Zones`.
- `estimulos.md`: si se aprueban los arbustos densos, documentarlos como obstáculo opaco para la linterna.

## 11. Pendientes de aprobar

1. **Arbustos densos** que bloquean luz y visión, pero no el movimiento (§4).
2. **StreamingEnabled** activado con radio 512 (§7).
3. Mover `EnemySpawns` y `PatrolPoints` a `ServerStorage`, solo si el playtest demuestra que su lectura por el cliente importa (§8).

## 12. Pruebas en Studio

- Recorrer cada sendero cronometrando caminata y carga pesada, y comparar con la tabla de §4.
- Desde cada zona, empezar a volver al inicio de un atardecer forzado y confirmar que se llega desde todas menos desde la mina.
- Comprobar que no se nada en ningún punto del pantano ni del arroyo.
- Confirmar que la mina queda negra sin linterna a mediodía.
- Comprobar que la torre se ve desde el claro de día y desaparece con la niebla de la noche 1.
- Con la fogata encendida, medir que la puerta de la caseta queda dentro del radio en las noches 1 y 2 y fuera desde la 3, y que la radio nunca queda dentro.
- Ejecutar `ValidateStudio` con un marcador borrado, un `Id` duplicado y un tag mal puesto: los tres deben impedir la run con la ruta correcta.
- Pathfinding de un modelo del tamaño de la criatura desde cada `Noche_*` hasta cada `SiegeStart`, y desde el nido hasta la boca de la mina.
