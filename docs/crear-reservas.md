# Crear reservas

Este documento describe la utilizacion del flujo de creacion de reservas de salida en la app Flutter Golf y el contrato tecnico que usa con el backend.

## Alcance

El flujo actual permite crear una reserva de salida para un dia y una hora disponibles. No incluye, en el codigo actual, edicion ni cancelacion de reservas ya creadas.

Codigo principal relacionado:

- `lib/main.dart`: pantallas, validaciones, formateo de fechas/horas y control del flujo.
- `lib/services/datos_servidor_service.dart`: llamadas HTTP al backend.
- `test/widget_test.dart`: prueba del flujo completo de reserva.
- `test/services/datos_servidor_service_test.dart`: pruebas de construccion de queries de agenda.

## Prerrequisitos

Para poder acceder a `Reservar Salida`, la app necesita:

- Un usuario cargado en memoria local.
- Usuario marcado como registrado (`saved_user_registered = true`).
- `idUsuario` no vacio.
- Un `idCampo`; si no hay campo guardado, se usa por defecto `1`.

El boton `Reservar Salida` se habilita desde la pantalla principal cuando hay informacion de usuario y el usuario esta registrado. Si falta el `idUsuario`, la app muestra:

```text
No se pudo identificar el usuario para reservar.
```

## Datos internos usados

| Dato | Origen | Uso |
| --- | --- | --- |
| `idUsuario` | Informacion del usuario guardada | Se envia como `idUsuarioCreador` al crear la reserva. |
| `idCampo` | `saved_field_id` o valor por defecto `1` | Se usa para leer la configuracion de agenda del campo. |
| `idPartida` | Partida activa, partida guardada o id nuevo generado | Se asocia a la reserva creada. |
| `dia` | Dia elegido en calendario | Se envia al backend en formato `yyMMdd`. |
| `desde` | Hora validada de inicio | Se envia al backend en formato `HHmm`. |
| `hasta` | `desde + lapsus_agenda` | Se envia al backend en formato `HHmm`. |

Si no existe partida activa ni partida guardada, la app genera un `idPartida` aleatorio de 10 caracteres con letras mayusculas y numeros.

## Flujo de uso

1. En la pantalla principal, pulsar `Reservar Salida`.
2. Seleccionar un dia en el calendario.
3. Revisar la banda de disponibilidad.
4. Introducir una hora.
5. Pulsar `Comprobar ahora`.
6. Si la hora queda disponible, pulsar `Reservar`.
7. En la pantalla `Reserva efectuada`, pulsar `Entendido` para volver a la pantalla principal.

## Seleccion de dia

La pantalla `Selecciona el dia` muestra un calendario mensual:

- Empieza en el mes actual.
- Permite avanzar a meses futuros.
- Permite volver hacia atras solo hasta el mes actual.
- Los dias anteriores al dia actual aparecen deshabilitados.
- El dia actual se resalta visualmente.

Cuando se selecciona un dia, se transforma a formato de agenda:

```text
yyMMdd
```

Ejemplo:

```text
28/04/2026 -> 260428
```

## Carga de disponibilidad

Al entrar en la pantalla de hora, la app carga en paralelo:

- Reservas ocupadas del dia: `obtener_agenda`.
- Duracion de cada reserva: `coje_configuracion_campos` con `lapsus_agenda`.
- Hora inicial de agenda: `coje_configuracion_campos` con `agenda_desde`.
- Hora final de agenda: `coje_configuracion_campos` con `agenda_hasta`.

Si cualquiera de estos datos falla o es invalido, se muestra:

```text
No se pudo cargar la agenda.
```

En ese estado aparece el boton `Reintentar`, que vuelve a ejecutar la carga.

## Banda de disponibilidad

La pantalla de hora muestra una banda horizontal:

- Verde: tramos libres.
- Rojo: tramos ocupados.
- Hora izquierda: inicio de agenda.
- Hora derecha: fin de agenda.

Los tramos libres tienen tooltip con el rango:

```text
libre de HH:mm a HH:mm
```

Los tramos ocupados se calculan desde las reservas devueltas por el backend. Si hay reservas ocupadas solapadas o contiguas, la banda las fusiona visualmente.

## Entrada de hora

El campo `Hora` usa teclado numerico y normaliza la entrada:

| Entrada | Resultado en UI |
| --- | --- |
| `930` | `9:30` |
| `0930` | `09:30` |
| `1030` | `10:30` |

La validacion acepta internamente:

- `HH:mm`
- `H:mm`
- `HHmm`
- `Hmm`

La hora debe representar un valor real entre `00:00` y `23:59`.

## Comprobacion de hora

Antes de reservar, el usuario debe pulsar `Comprobar ahora`. La app valida:

- La agenda ya esta cargada.
- La configuracion de agenda es valida.
- La hora introducida es valida.
- El rango `desde` - `hasta` cabe dentro de `agenda_desde` y `agenda_hasta`.
- El rango no se solapa con ningun tramo ocupado.

Si todo es correcto, aparece:

```text
Hora disponible
```

Y el boton cambia de `Comprobar ahora` a `Reservar`.

Si el usuario edita la hora despues de comprobarla, se limpia el estado de comprobacion y hay que volver a pulsar `Comprobar ahora`.

## Ajuste automatico de hora

Al comprobar, la app ajusta la hora introducida al tramo libre mas cercano de la parrilla definida por `lapsus_agenda`.

Ejemplo con:

```text
agenda_desde = 10:00
agenda_hasta = 11:00
lapsus_agenda = 15
ocupado = 10:25 - 10:40
```

Si el usuario escribe:

```text
1030
```

La app puede ajustar a:

```text
10:45
```

porque el rango `10:45 - 11:00` es el primer tramo valido y libre mas cercano.

Reglas del ajuste:

- Los candidatos empiezan en `agenda_desde`.
- Cada candidato avanza `lapsus_agenda` minutos.
- Solo se consideran candidatos cuyo fin no supera `agenda_hasta`.
- Se elige el candidato libre mas cercano a la hora escrita.
- Si hay empate de distancia, se prioriza el candidato posterior.
- Si no hay ningun tramo libre cercano, se muestra:

```text
No hay una hora libre cercana
```

## Reglas de solape

Una reserva nueva ocupa el rango:

```text
desde <= hora < hasta
```

La app considera que hay solape cuando:

```text
nuevo_desde < ocupado_hasta && nuevo_hasta > ocupado_desde
```

Por tanto:

- `10:40 - 10:55` no se solapa con una reserva que termina justo a `10:40`.
- `10:30 - 10:45` si se solapa con una reserva `10:25 - 10:40`.

## Creacion de la reserva

Cuando se pulsa `Reservar`, la app:

1. Vuelve a validar la hora.
2. Calcula `hasta = desde + lapsus_agenda`.
3. Convierte `desde` y `hasta` a formato compacto `HHmm`.
4. Llama a `inserta_agenda`.
5. Acepta la reserva solo si la respuesta del backend contiene `rpta = ok`.

Mientras se ejecuta la llamada, el boton muestra:

```text
Reservando...
```

Si el backend responde correctamente, se abre la pantalla:

```text
Reserva efectuada
```

La pantalla de exito muestra la fecha y la hora de inicio. Al pulsar `Entendido`, la navegacion vuelve a la pantalla principal.

Si la llamada falla o la respuesta no es `ok`, se muestra:

```text
No se pudo efectuar la reserva.
```

## Contrato backend

Todas las llamadas se hacen por `GET` al endpoint:

```text
https://autopowersoft.com/obtenerJSON/obtenerJSON.aspx
```

La cabecera usada es:

```text
Accept: text/plain
```

El timeout por defecto del servicio es de 20 segundos.

### Obtener agenda

Metodo Flutter:

```dart
DatosServidorService.obtenerAgenda(String dia)
```

Query:

```text
accion=obtener_agenda
dia=yyMMdd
```

Ejemplo:

```text
https://autopowersoft.com/obtenerJSON/obtenerJSON.aspx?accion=obtener_agenda&dia=260428
```

Respuesta esperada:

```json
[
  {
    "desde": "1025",
    "hasta": "1040",
    "idPartida": "11223"
  }
]
```

La app tambien tolera JSON con comillas simples:

```text
[{'desde':'1025','hasta':'1040','idPartida':'11223'}]
```

Y respuestas envueltas en claves como:

- `agenda`
- `data`
- `valor`
- `json`

Cada fila valida debe tener:

- `desde`: hora compacta `HHmm`.
- `hasta`: hora compacta `HHmm`.
- `idPartida`: opcional para mostrar o conservar referencia.

Las filas invalidas se ignoran.

### Leer configuracion de campo

Metodo Flutter:

```dart
DatosServidorService.cojeConfiguracionCampos(String idCampo, String parametro)
```

Query:

```text
accion=coje_configuracion_campos
idCampo=<idCampo>
parametro=<parametro>
```

Parametros usados por reservas:

| Parametro | Significado | Ejemplo valido |
| --- | --- | --- |
| `lapsus_agenda` | Duracion de cada reserva en minutos | `15` |
| `agenda_desde` | Hora de inicio de agenda | `10:00` o `1000` |
| `agenda_hasta` | Hora de fin de agenda | `18:00` o `1800` |

`lapsus_agenda` debe ser un entero mayor que cero.

`agenda_desde` y `agenda_hasta` deben ser horas validas, y `agenda_desde` debe ser menor que `agenda_hasta`.

La app acepta valores directos, strings JSON o mapas con claves como:

- `valor`
- `rpta`
- `lapsus_agenda`
- `agenda_desde`
- `agenda_hasta`

### Insertar agenda

Metodo Flutter:

```dart
DatosServidorService.insertarAgenda({
  required String dia,
  required String desde,
  required String hasta,
  required String idPartida,
  required String idUsuarioCreador,
})
```

Query:

```text
accion=inserta_agenda
dia=yyMMdd
desde=HHmm
hasta=HHmm
idPartida=<idPartida>
idUsuarioCreador=<idUsuario>
```

Ejemplo:

```text
https://autopowersoft.com/obtenerJSON/obtenerJSON.aspx?accion=inserta_agenda&dia=260428&desde=1045&hasta=1100&idPartida=ABC123XYZ9&idUsuarioCreador=123
```

Respuesta correcta:

```json
{"rpta":"ok"}
```

Tambien se acepta:

```text
{'rpta':'ok'}
```

Cualquier otra respuesta se trata como error de creacion.

## Formatos

| Concepto | Formato | Ejemplo |
| --- | --- | --- |
| Dia de agenda | `yyMMdd` | `260428` |
| Hora para backend | `HHmm` | `1045` |
| Hora visible | `HH:mm` | `10:45` |
| Duracion | Minutos enteros | `15` |
| Respuesta ok | Campo `rpta` con valor `ok` | `{"rpta":"ok"}` |

## Estados y mensajes

| Situacion | Mensaje visible |
| --- | --- |
| Usuario sin `idUsuario` | `No se pudo identificar el usuario para reservar.` |
| Agenda cargando | `Agenda cargando` |
| Agenda no cargada o invalida | `Agenda no disponible` |
| Error cargando agenda | `No se pudo cargar la agenda.` |
| Hora vacia o invalida | `Introduce una hora valida (HH:mm o HHmm)` |
| Rango fuera de agenda | `Hora fuera de horario` |
| Rango ocupado | `Hora ocupada (HH:mm - HH:mm)` |
| Sin tramo libre cercano | `No hay una hora libre cercana` |
| Hora comprobada correctamente | `Hora disponible` |
| Error creando reserva | `No se pudo efectuar la reserva.` |
| Reserva creada | `Reserva efectuada` |

## Pruebas existentes

Hay cobertura automatizada para:

- Apertura del flujo desde `Reservar Salida`.
- Seleccion del dia actual.
- Carga de agenda y configuracion.
- Renderizado de banda libre/ocupada.
- Ajuste de una hora ocupada a la hora libre mas cercana.
- Envio de `inserta_agenda` con `dia`, `desde`, `hasta`, `idPartida` e `idUsuarioCreador`.
- Construccion de queries de `obtener_agenda` e `inserta_agenda`.

Comandos utiles:

```bash
flutter test test/widget_test.dart
flutter test test/services/datos_servidor_service_test.dart
```
