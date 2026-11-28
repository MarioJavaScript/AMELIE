# GDD: juego de terror y supervivencia co-op (Roblox)

Estado: **aprobado por Mario (2026-11-16)**, con 3 ajustes (ver sección 7). Solo queda pendiente D4 (nombre).
Los números de este documento son objetivos de diseño. En código van en `src/shared/config/` (sobre todo `NightsConfig`), nunca hardcodeados.

---

## 0. Decisiones D1-D4

| # | Decisión | Recomendación | Estado |
|---|----------|---------------|--------|
| D1 | Modo de juego | Co-op 1-4 jugadores por servidor, partida por "run" (una partida dura ~45-55 min y termina en victoria o derrota). | **Aprobado** |
| D2 | Qué se guarda | Solo progreso meta: partidas jugadas, victorias, noche máxima alcanzada, piezas recuperadas, desbloqueos cosméticos (post-MVP). La base y el inventario NO se guardan entre partidas. | **Aprobado** |
| D3 | Objetivo principal | "Señal de rescate", detallado en la sección 2. | **Aprobado** |
| D4 | Codename | Propuesta: **"Frecuencia Muerta"**. Alternativas: "Última Señal", "Estática". | **[pendiente de aprobar]** |

---

## 1. Premisa y loop de una partida

### Premisa
Un grupo de 1 a 4 personas queda varado en un bosque aislado tras un accidente. En un claro hay una caseta de guardabosques con una radio de emergencia rota. Algo vive en el bosque y caza de noche. La única salida es reparar la radio, transmitir la señal y aguantar hasta que llegue el rescate.

Un río encajonado parte la zona en dos. Al sur, el territorio donde están varados: un pueblo evacuado a toda prisa y una mina abandonada. Al norte, tras un puente volado, el distrito industrial, un bosque que ya no parece de este mundo y el complejo científico de donde salió la criatura. El sur muestra las consecuencias; el norte esconde el origen (sección 2.0).

### Estructura de tiempo
La partida es una secuencia de ciclos **Día → Atardecer → Noche**. Hay **5 noches** (ver sección 3).

| Fase | Duración objetivo | Qué se hace |
|------|-------------------|-------------|
| Día | 4.5 min (Día 1: 6 min) | Explorar, recolectar, buscar piezas, construir y reparar. La criatura no caza, pero hay señales de su presencia. |
| Atardecer | 45 s | Aviso claro de que viene la noche: luz naranja, la niebla empieza a entrar, sonido ambiente cambia. Tiempo para volver a la base. |
| Noche | 4-6 min (crece cada noche) | Sobrevivir. Defender la base, mantener la fogata, salir solo si vale el riesgo. |
| Amanecer | 15 s | Respiro. La criatura se retira. Reaparecen los jugadores caídos. Resumen breve de la noche. |

### Loop de una partida, de principio a fin

1. **Lobby (30 s máx.)**: los jugadores entran al servidor. La partida empieza cuando todos están listos o al acabar el contador.
2. **Llegada (Día 1)**: cinemática corta o texto en pantalla (sin voces en MVP). Los jugadores aparecen en el claro junto a la caseta de radio. Cada uno tiene linterna con batería parcial. La radio muestra 4 huecos vacíos: es el objetivo visible desde el primer minuto.
3. **Día 1, preparación**: talar y picar cerca de la base, craftear hacha y pico, encender la fogata principal, poner las primeras paredes. Es el día más largo para aprender sin presión.
4. **Primera noche**: la criatura aparece por primera vez. Solo investiga y asusta; no rompe paredes. Sirve para enseñar las reglas de luz y ruido.
5. **Días 2-4, expediciones en dos actos**: primero las dos piezas del territorio inicial (gasolinera y mina) y los recursos para reconstruir el puente; con el puente en pie, las dos piezas del territorio avanzado (distrito industrial y complejo científico). Llevar una pieza de vuelta a la base e instalarla en la radio es el avance principal. Mientras tanto hay que mantener la base (paredes, fogata, pilas).
6. **Noches 2-4, asedio creciente**: la criatura ataca la base y rompe paredes. Desde la noche 3 hay acechadores en el territorio avanzado; llegan a la base en cuanto el puente está construido.
7. **Radio completa**: con las 4 piezas instaladas, la radio queda lista. La transmisión solo se puede iniciar **de noche** (ver 2.3).
8. **Noche de transmisión (noche final)**: la radio hace ruido constante y atrae a todo el bosque. El grupo defiende la caseta hasta que termina la transmisión y amanece.
9. **Rescate**: al amanecer llega el rescate. Pantalla de victoria con estadísticas.
10. **Fin**: se guarda el progreso meta (D2) y se vuelve al lobby.

Si el grupo es aniquilado o se acaba el tiempo, la partida termina en derrota (sección 4).

### Loop corto (minuto a minuto)
Explorar → recolectar → oír una señal → decidir (seguir o volver) → volver con recursos o una pieza → reforzar la base → aguantar la noche.
La tensión de cada día es **avaricia contra seguridad**: cada minuto más fuera de la base da más recursos, pero acerca el atardecer.

### Hambre (MVP, sencilla)
Una barra de hambre que baja lento (llena dura unos 20 min). En 0, la estamina no se regenera y se pierde vida poco a poco, sin llegar a derribar por sí sola. Se come con **latas** (loot de la ciudad y del distrito industrial) y **bayas** (arbustos recolectables del bosque normal del territorio inicial). Es una presión de fondo que empuja a salir de la base, no un sistema de gestión. La sed queda fuera del MVP. Valores en `PlayerConfig.Hunger` ([jugador](specs/jugador.md)).

---

## 2. Objetivo principal: "Señal de rescate"

### 2.0 El mundo en dos actos

El mapa se divide en dos territorios separados por un río encajonado. Layout completo en [mapa.md](specs/mapa.md).

| Territorio | Zonas | Papel |
|---|---|---|
| **Inicial (acto 1)** | Safe Zone (base), ciudad abandonada con gasolinera, mina abandonada. Torre de vigilancia como mirador opcional | Aprender, recolectar, primeras 2 piezas. Muestra las consecuencias: evacuación interrumpida, control militar destruido, campamento minero abandonado |
| **Avanzado (acto 2)** | Distrito industrial, bosque anómalo, complejo científico (con el nido en sus sótanos) | Últimas 2 piezas, más peligro, escoltas largas. Esconde el origen: pistas de una investigación previa que unen el complejo, el distrito y el bosque, sin revelar el experimento ni qué es la criatura |

Reglas:
- **El puente es la única conexión transitable para los jugadores.** Está volado. El río no se puede vadear hacia el norte (la orilla norte es una pared de roca) y no se puede rodear (montañas y límites del mapa). La geografía impide saltarse la progresión.
- **Reconstruir el puente** cuesta los recursos del acto 1 y es una obra ruidosa junto al agua (construccion.md, Fase 3). Sin temporizadores: el coste está pensado para que el puente caiga hacia la mitad de una partida de ~54 min (día 3 en un grupo normal). Un grupo eficiente puede tenerlo antes; uno lento, después.
- **La criatura principal cruza el río a nado** desde la noche 1: el puente no la frena y la curva de la sección 3 no cambia.
- **Los acechadores anómalos no nadan.** Viven en el territorio avanzado desde la noche 3 y solo cruzan al territorio inicial por el puente construido. Construir el puente abre el camino a las piezas y también a ellos: es la escalada del acto 2.
- **La mina ya no es el nido.** Es dificultad media: exploración subterránea a oscuras y recursos minerales. El nido está en las instalaciones profundas del complejo científico.
- **El bosque anómalo** es consecuencia de los experimentos: vegetación alterada, bioluminiscencia y restos de la investigación. Queda preparado (volúmenes `AnomalyZone`) para mecánicas futuras de niebla, interferencia electromagnética y terror auditivo, que no entran en el MVP. A futuro, la anomalía podrá propagarse visualmente alrededor del puente.

### 2.1 Las piezas

La radio necesita **4 piezas** (4 en MVP, 5ª pieza post-MVP). Cada pieza está en una zona fija del mapa. Dentro de cada zona, la pieza aparece en **uno de 3 puntos posibles**, elegido al azar al empezar la partida, para que cada run sea un poco distinta.

Dentro de cada acto **el orden es libre**. Las piezas del acto 2 exigen el puente.

| # | Pieza | Zona | Acto | Distancia a la base | Por qué es peligrosa |
|---|-------|------|------|---------------------|----------------------|
| 1 | **Batería** | Gasolinera de la ciudad abandonada | 1 | Cerca (~230 studs) | Es la zona "tutorial". El peligro es bajo pero real: estanterías y coches donde hay que buscar haciendo ruido (abrir puertas metálicas y cajones suena). Buena para aprender el sistema de ruido de día. |
| 2 | **Cristal de frecuencia** | Mina abandonada al pie de la montaña oeste | 1 | Media (~380 la entrada, hasta ~600 dentro) | Oscuridad total: la linterna es obligatoria. Túneles largos, gateras estrechas y una caverna al fondo. De día está vacía; de noche la criatura puede entrar. Las rocas de dentro tientan a picar (ruido). |
| 3 | **Antena** | Azotea de una nave del distrito industrial | 2 | Lejos (~530 studs) | Es **pesada** (ver 2.2): quien la carga no puede correr ni usar escaleras de mano. Para bajarla de la azotea hay que soltarla por el pretil, y el golpe se oye. Luego hay que escoltarla hasta el puente y la base por terreno abierto. |
| 4 | **Transceptor** | Complejo científico, desde el laboratorio hasta junto al nido | 2 | Muy lejos (~650-700 studs) | Dos sótanos sin luz. **De día la criatura duerme en el nido**: si alguien hace ruido fuerte cerca, despierta y caza aunque sea de día. Es la única pieza que puede costar la partida en pleno día. |

Las distancias son orientativas para el greybox (F1-1); se ajustan en el playtest.

### 2.2 Reglas de las piezas

- **Recoger**: interactuar con la pieza (mantener pulsado ~2 s). El servidor valida la distancia.
- **Cargar**: una pieza ocupa las manos. Quien la carga no puede usar herramientas ni construir.
- **Piezas pesadas (Antena)**: quien la carga camina más lento y no puede correr. Obliga a escoltar.
- **Soltar**: si el portador cae o la suelta, la pieza queda en el suelo con un brillo tenue visible para el grupo. No desaparece nunca.
- **Instalar**: llevarla a la radio e interactuar. Al instalarla, la radio hace un sonido de estática y se enciende una luz en el panel: feedback de progreso claro para todo el grupo.
- **Progreso compartido**: las piezas son del grupo, no de un jugador. Lo decide el servidor (ObjectiveService).
- **Pilas y chatarra**: cada zona tiene además pilas de linterna y algo de material raro. Así las expediciones valen la pena aunque la pieza ya esté recogida.

### 2.3 La transmisión

- Con las 4 piezas instaladas, la radio queda completa. Solo se puede **iniciar la transmisión de noche** (la radio "necesita la ionosfera nocturna"; es la excusa para que el clímax sea de noche).
- La transmisión dura **3 minutos**. Durante ese tiempo la radio emite ruido constante, que es el estímulo más fuerte del juego: atrae a la criatura y a todos los acechadores hacia la caseta.
- Si la criatura golpea la radio, la transmisión **se pausa** hasta que alguien la reactiva (interactuar 3 s junto a la radio). La radio no se destruye; esto evita derrotas injustas y crea momentos de "alguien tiene que salir a reactivarla".
- Cuando la transmisión termina, hay que **sobrevivir hasta el amanecer** de esa noche. Al amanecer llega el rescate y se gana.
- **Transmitir antes de la noche 5** está permitido: esa noche se convierte en la noche final, con la dificultad de esa noche más el frenesí de la transmisión. Es riesgo contra recompensa (y una estadística de "rescate temprano").

---

## 3. Curva de dificultad noche por noche

**5 noches**. Con 5 la partida queda en ~54 min (días 4.5 min, día 1 de 6 min), que es una sesión razonable en Roblox. Con menos noches no da tiempo a las 4 expediciones; con más, el medio de la partida se repite.

### Tabla de diseño (valores iniciales para `NightsConfig`)

| | Noche 1 | Noche 2 | Noche 3 | Noche 4 | Noche 5 (final) |
|---|---|---|---|---|---|
| Duración | 4 min | 4.5 min | 5 min | 5.5 min | 6 min |
| Criatura principal | Sí | Sí | Sí | Sí | Sí |
| Acechadores anómalos (máx. a la vez) | 0 | 0 | 2 | 3 | 4 |
| ¿Rompe paredes? | No | Sí, lento | Sí | Sí, rápido | Sí, rápido |
| Ataques a la base | Ninguno, solo ronda | 1 asedio | 2 asedios | 2 asedios largos | Constante |
| Niebla (visibilidad aprox.) | 120 studs | 100 | 80 | 60 | 45 |
| Multiplicador de radio de detección | x1.0 | x1.1 | x1.25 | x1.4 | x1.6 |
| Consumo de la fogata | x1.0 | x1.0 | x1.25 | x1.5 | x1.5 |
| Radio seguro de la fogata | 12 studs | 10 | 8 | 6 | 0 (no hay zona segura) |
| ¿Acechadores apagan la fogata? | — | — | Sí | Sí | Sí |

Los acechadores (en el código `AcechadorMenor`) nacen en el territorio avanzado. Su máximo se aplica igual, pero mientras el puente siga roto no pueden llegar a la base: asedian solo si el puente está construido.

### Qué cambia en cada noche y para qué sirve

- **Noche 1, "Algo está ahí fuera"**: enseña las reglas. La criatura se acerca a la base, rodea la fogata, se deja ver un instante en el borde de la luz y se va. Investiga luces y ruidos, pero si atrapa a alguien solo lo derriba, nunca lo mata (no hay muertes en la noche 1). El objetivo es que el jugador aprenda "la luz y el ruido la traen" sin castigo.
- **Noche 2, "Prueba las paredes"**: primer asedio real. La criatura golpea un punto de la base hasta romperlo. Enseña que las paredes son tiempo, no seguridad. A partir de aquí se puede morir.
- **Noche 3, "No está sola"**: aparecen los acechadores anómalos, más débiles y más rápidos, que salen del bosque anómalo. La luz directa de la linterna los hace retroceder (contrapeso: la luz atrae a la criatura principal). Si el puente está construido, cruzan y los ataques llegan desde dos lados a la vez; los acechadores pueden **apagar la fogata** si llegan a ella: hay que defenderla. Si el puente sigue roto, solo los encuentra quien esté en el territorio avanzado.
- **Noche 4, "Sabe dónde duermes"**: la criatura aprende. Ataca el punto más débil de la base (la pared con menos HP) en vez de uno al azar y los asedios duran más. Si alguien sale solo, la criatura lo prioriza sobre la base.
- **Noche 5, "Luna roja"**: la noche más larga y con más niebla. Si el grupo transmite, la criatura entra en frenesí: deja de acechar y va directa a la radio. Si el grupo no ha completado la radio, esta es su última oportunidad (ver sección 4).

### Escalado por número de jugadores

| Jugadores | Acechadores | HP de paredes | Recursos por golpe |
|-----------|-------------|---------------|--------------------|
| 1 | x0.5 (redondeado hacia abajo) | x1.25 | x1.5 |
| 2 | x0.75 | x1.0 | x1.2 |
| 3 | x1.0 | x1.0 | x1.0 |
| 4 | x1.0 | x1.0 | x1.0 |

La criatura principal es siempre una sola. Con 1 jugador hay reglas extra de reaparición (sección 4).

### Días
Los días también escalan, pero poco: desde el día 3 aparecen rastros (huellas, árboles arañados, animales muertos) más cerca de la base, y desde el día 4 puede haber un **avistamiento diurno** (la criatura se ve a lo lejos entre los árboles o en la otra orilla del río, sin atacar). Es tensión gratis, sin aumentar la dificultad real.

---

## 4. Condiciones de victoria y derrota

### Victoria
- Las 4 piezas instaladas, la transmisión completada y **al menos un jugador vivo al amanecer** de esa noche.
- Los jugadores que estaban caídos o espectando al amanecer también cuentan como rescatados.

### Derrota
Dos formas de perder, nada más.

1. **Aniquilación**: todos los jugadores están caídos o muertos al mismo tiempo durante una noche.
2. **Sin tiempo**: amanece el día 6 sin haber completado la transmisión. Narrativa: la criatura ya no se retira de día. Mecánicamente, pantalla de derrota al amanecer.

**Por qué no "fogata destruida = derrota"**: perder por un objeto que se apaga se siente injusto y es difícil de leer en plena noche. La fogata apagada ya castiga bastante (sección 5). La radio tampoco se destruye; solo pausa la transmisión.

### Caer, revivir y reaparecer
- Con 0 HP el jugador queda **caído**: se arrastra lento, ve en blanco y negro y puede gritar (sonido que atrae).
- Un compañero puede **revivirlo** manteniendo interacción 4 s. Revivir hace ruido.
- Si nadie lo revive en 30 s, o si la criatura lo remata, el jugador **muere**: pasa a espectador hasta el amanecer.
- Al amanecer, los muertos reaparecen en la base con linterna y sin el resto del inventario. Lo que llevaban queda en una mochila donde murieron.
- **1 jugador**: no hay quien reviva. Tiene 1 "segunda oportunidad" **por noche**: la primera vez que cae en una noche, se levanta solo tras 10 s. Si vuelve a caer esa misma noche, derrota. Se recarga al amanecer.

---

## 5. Cómo se genera el miedo

### Principios
1. **Lo que no se ve asusta más que lo que se ve.** La criatura se oye mucho más de lo que se ve. Las apariciones completas son raras y cortas.
2. **Siempre hay aviso.** La criatura nunca ataca sin al menos una señal previa (sonido, luz que parpadea, silencio). El miedo debe venir de la anticipación, no de muertes que se sienten injustas.
3. **Las herramientas que te salvan te delatan.** Linterna, fogata, correr, construir: todo lo útil hace luz o ruido. Cada decisión es un riesgo.
4. **Tensión en olas, no constante.** Después de un pico tiene que haber un respiro, o el jugador se acostumbra y deja de asustarse.

### Escalera de avisos de la criatura
La criatura se anuncia en este orden según se acerca. Cada nivel es más corto y más claro que el anterior. Los umbrales concretos los define F4-1/F4-2.

| Nivel | Distancia aprox. | Señal |
|-------|------------------|-------|
| 0. Presencia | En la zona | El sonido ambiente (insectos, pájaros, viento en hojas) **se apaga de golpe**. El silencio es la primera alarma. |
| 1. Lejos | 80-120 studs | Un llamado lejano y grave. Direccional (audio 3D) pero difícil de ubicar. |
| 2. Cerca | 30-80 studs | Pasos pesados, ramas que crujen, respiración. Ya se puede ubicar de dónde viene. |
| 3. Muy cerca | < 30 studs | La linterna **parpadea**. Leve distorsión de color en pantalla. Latido en el audio del jugador. |
| 4. Ataque | Contacto | Chillido corto, la criatura aparece en el campo de visión, golpe. |

Si el jugador se queda quieto, a oscuras y en silencio en el nivel 2-3, la criatura puede pasar de largo. Ese es el momento de más tensión del juego y debe ser posible sobrevivirlo.

### Luz

| Fuente | Qué hace a favor | Qué hace en contra |
|--------|------------------|--------------------|
| **Linterna** | Ver de noche, en la mina y en los sótanos del complejo. Desde la noche 3, hace retroceder a los acechadores anómalos. | La criatura la detecta a gran distancia. Gasta batería. Las pilas escasean. |
| **Fogata principal** | Zona segura: la criatura **no entra** en su radio de luz cercana mientras esté encendida. El radio **se achica cada noche** (12 → 10 → 8 → 6 → 0 studs, ver sección 3), así que quedarse pegado al fuego no es una estrategia que gane la partida. Calor = regenera salud lenta. | Se ve desde todo el mapa: la criatura siempre sabe dónde está la base. Consume madera. Desde la noche 3 los acechadores pueden apagarla (si el puente les deja llegar). |
| **Oscuridad total** | Es la mejor forma de esconderse. | No ves nada. La niebla y el sonido son tu única información. |

**Fogata apagada**: la base pierde la zona segura y la criatura puede entrar hasta la radio. Volver a encenderla tarda 5 s y hace ruido. Mantener la fogata es una tarea constante de noche: alguien tiene que salir a por madera o tenerla guardada.

### Ruido
Cada acción emite un evento de ruido con un radio. La criatura investiga el ruido más fuerte que oiga. Valores iniciales (van en config):

| Acción | Radio de ruido |
|--------|----------------|
| Caminar agachado | 0 (silencio) |
| Caminar | 10 studs |
| Caminar en agua (orilla del río) | 25 studs |
| Correr | 35 studs |
| Talar / picar | 50 studs |
| Construir / reparar | 45 studs |
| Abrir puertas metálicas, cajones (gasolinera) | 30 studs |
| Revivir a un compañero | 30 studs |
| Grito de jugador caído | 60 studs |
| Radio transmitiendo | Todo el mapa |

El chat de voz de Roblox **no** genera ruido en el juego en el MVP. **[post-MVP sería una mecánica muy buena pero requiere voz habilitada y es injusto para quien no la tiene]**

### Momentos de tensión diseñados
- **El atardecer**: la cuenta atrás de 45 s con la luz cambiando es la fuente de tensión más fiable del juego. Volver con una pieza pesada contra el reloj.
- **El complejo**: bajar dos sótanos a oscuras, encender la linterna sabiendo que la criatura duerme ahí abajo.
- **El puente**: construirlo junto al agua por donde cruza la criatura, sabiendo que al terminarlo también se abre el paso a los acechadores.
- **La mina**: túneles largos y gateras sin luz; no hay nido, pero de noche no está garantizado que esté vacía.
- **El bosque anómalo**: luz que no es de la fogata, árboles que no son de aquí y un silencio que no se rompe.
- **La fogata baja**: la llama se reduce visiblemente cuando queda poca madera. Todo el grupo lo ve.
- **La pared que cruje**: durante un asedio, la pared golpeada muestra grietas y suena distinto a medida que pierde HP. Todos saben por dónde va a entrar.
- **El silencio a mitad de la noche**: la criatura se retira un rato. Que no pase nada también asusta.
- **Avistamientos diurnos** (día 4+): verla de lejos a plena luz rompe la sensación de "de día estoy a salvo".

### Ritmo dentro de la noche ("director" simple)
Un sistema en el servidor controla la intensidad para que haya olas:
- **Subida**: la criatura ronda, avisos de nivel 1-2.
- **Pico**: asedio o caza activa.
- **Respiro**: tras un pico (un asedio, o un jugador caído), al menos 45-60 s en los que la criatura se aleja.
- La cantidad de picos por noche sigue la tabla de la sección 3 (columna "Ataques a la base").

En el MVP el director es solo un temporizador de fases dentro de la noche. Post-MVP puede medir el estrés real de cada jugador (vida, distancia a la criatura, luz).

---

## 6. Alcance del MVP

### Entra en el MVP

| Área | Incluye |
|------|---------|
| Partida | Co-op 1-4, lobby simple, 5 noches, victoria y derrota, pantalla final con estadísticas |
| Mapa | 1 mapa en dos territorios unidos por un puente reconstruible: base, ciudad con gasolinera y mina (acto 1); distrito industrial, bosque anómalo y complejo científico (acto 2). 4 zonas de piezas con 3 puntos de aparición cada una. Torre como mirador secundario |
| Objetivo | 4 piezas, radio con 4 huecos, transmisión de 3 min, rescate al amanecer |
| Jugador | Primera persona, estamina, salud, hambre sencilla, agacharse, linterna con batería, caer/revivir/reaparecer |
| Recursos | Madera, piedra, pilas, chatarra, comida (latas y bayas) |
| Herramientas y consumibles | Hacha, pico (crafteo rápido), vendas, botiquín, comida |
| Construcción | Cimiento, pared, marco con puerta, fogata; reparar; HP de estructuras |
| Enemigos | Criatura principal + 1 tipo de acechador menor (la misma IA con otros parámetros) |
| Terror | Escalera de avisos, ruido y luz como estímulos, niebla por noche, atardecer, director simple por fases |
| Audio | Ambiente día/noche, pasos, golpes, criatura (llamado, pasos, chillido), estática de la radio |
| Guardado | Solo progreso meta (D2 = A) |
| UI | HUD (vida, estamina, hambre, batería, hora), inventario, crafteo, panel de objetivos (piezas X/4), fin de partida |

### Queda fuera del MVP

- 5ª pieza de radio y zonas extra.
- Objetivos secundarios diarios ("consigue 10 de madera", etc.).
- Sed, frío, clima dinámico. (El hambre sencilla sí entra, ver sección 1.)
- Varios mapas o mapa procedural.
- Más tipos de enemigos o jefes.
- Armas para matar a la criatura. **No se puede matar a la criatura principal** (se puede aturdir con luz/ruido post-MVP).
- Chat de voz como fuente de ruido.
- Desbloqueos cosméticos, tienda, monetización.
- Niveles de dificultad seleccionables.
- Director avanzado que mide el estrés de cada jugador.
- Cinemáticas con cámara y voces.
- Guardado de la base (D2 = B).

---

## 7. Decisiones aprobadas (2026-11-16)

Aprobados por Mario: D1, D2, D3, 5 noches y tabla de dificultad, antena pesada, reglas de transmisión, derrota (aniquilación o día 6), caer/revivir/reaparecer, escalado por jugadores, director simple, criatura principal inmortal, voz sin ruido en MVP.

**Ajustes aplicados en la revisión:**
1. **Duración**: días de 4.5 min (día 1 de 6 min). La partida queda en ~54 min; antes las tablas sumaban ~62.
2. **Fogata**: el radio seguro se achica cada noche (12/10/8/6/0 studs) y desde la noche 3 los acechadores pueden apagarla. Evita que quedarse pegado al fuego sea la estrategia dominante.
3. **Segunda oportunidad en solitario**: una por noche en vez de una por partida.

**Pendiente:** D4, nombre del juego ("Frecuencia Muerta" es la propuesta).

### Rediseño del mundo en dos actos (2026-11-27)

Aprobado por Mario: dos territorios separados por un río; el puente como única conexión, reconstruido a mitad de partida sin tiempos artificiales; criatura principal que cruza a nado desde la noche 1; acechadores anómalos que solo cruzan por el puente construido; mina sin nido (dificultad media, minerales); nido en los sótanos del complejo científico; bosque anómalo preparado para mecánicas futuras; piezas en gasolinera, mina, distrito industrial y complejo; Antena en una azotea industrial; narrativa ambiental (consecuencias al sur, origen escondido al norte). El pantano desaparece y la torre queda como mirador opcional. Implementación del puente: Fase 3. En F1 solo hay un comando de debug en Studio.

### Hambre en el MVP (2026-11-27)

Aprobado por Mario: entra el hambre sencilla (barra que baja lento; en 0 no se regenera estamina y se pierde vida lento). Comida: latas en el loot de la ciudad y del distrito industrial, bayas recolectables en el bosque normal. Se añade el botiquín (cura mucho, lento, se interrumpe al recibir daño). La sed sigue fuera del MVP.

## 8. Siguientes documentos que dependen de este

- `docs/specs/enemigo.md` (F4-1, Opus 5.5): ficha de la criatura y del acechador, sonidos, aspecto, umbrales de la escalera de avisos.
- Spec de la máquina de estados de la IA (F4-2, Fable).
- Specs de sistemas y Remotes (F0-3, Astra), incluido ObjectiveService.
- `NightsConfig` (F5-1): pasar la tabla de la sección 3 a config.
