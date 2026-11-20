# Práctica Guiada Semana 11 — Arquitectura Offline-First en Flutter

**Desarrollo Móvil Integral · Unidad II · Ingeniería en Desarrollo de Software**

App de tareas que funciona **sin conexión**, usando SQLite como *Single Source of Truth*,
**WorkManager** para sincronizar en segundo plano y un ciclo **PUSH → ACK → PULL → MERGE**
bidireccional con resolución de colisiones **Last-Write-Wins + control de versiones**.

```
offline_first_tasks/   App Flutter (Android)
cloud_server/          Backend REST en Dart (shelf) + "Consola Nube" web
```

---

## 1. Cómo ejecutarlo

### 1.1 Backend ("la nube")

```bash
cd cloud_server
dart pub get
ADMIN_KEY=utxj2026 dart run bin/cloud_server.dart
```

En PowerShell: `$env:ADMIN_KEY='utxj2026'; dart run bin/cloud_server.dart`

* API: `http://localhost:8080`
* **Consola Nube**: `http://localhost:8080/?key=utxj2026` (se actualiza sola cada 1.5 s)
* Los datos persisten en `cloud_server/data/cloud_db.json`.

### 1.2 App Flutter

> **Firebase:** por seguridad, `android/app/google-services.json` y `lib/firebase_options.dart`
> no están en el repositorio. Antes de compilar, genéralos con tu propio proyecto de Firebase:
> ```bash
> dart pub global activate flutterfire_cli
> cd offline_first_tasks
> flutterfire configure
> ```

```bash
cd offline_first_tasks
flutter pub get
flutter run            # con el emulador encendido
flutter test           # 17 pruebas unitarias y de sincronización
```

* En el **emulador** la URL por defecto `http://10.0.2.2:8080` apunta al backend de tu PC.
* En un **celular físico por USB** (lo más simple, no necesita Wi-Fi):
  ```bash
  adb reverse tcp:8080 tcp:8080
  ```
  y en la app usa la URL `http://localhost:8080` (Login → *Servidor*).
* En un **celular físico por Wi-Fi** usa `http://IP-de-tu-PC:8080` (misma red, puerto 8080
  permitido en el firewall de Windows).

> **Windows:** guarda el proyecto en una ruta corta (p. ej. `C:\dev\practica_semana11`).
> Rutas muy largas superan el límite de 260 caracteres y el compilador de shaders falla.
> `android/gradle.properties` incluye `kotlin.incremental=false` para evitar el error
> *"Could not close incremental caches"* cuando el proyecto y el pub cache están en
> unidades distintas.

---

## 2. Arquitectura (Single Source of Truth)

```
 ┌──────────────┐  streams   ┌────────────────┐  PUSH/PULL   ┌──────────────────┐
 │  UI Flutter  │ ◄────────► │  SQLite local  │ ◄──────────► │  Backend (nube)  │
 │ (solo lee    │            │ fuente única   │  en segundo  │  REST + reglas   │
 │  streams)    │            │  de verdad     │    plano     │  por UID         │
 └──────────────┘            └────────────────┘              └──────────────────┘
```

* La UI **nunca** espera a la red: lee `Stream`s de SQLite → latencia percibida ~0 ms.
* Toda escritura va primero a disco con `is_synced = 0` (bandera sucia).
* La sincronización ocurre en segundo plano y vuelve a escribir en SQLite; los streams
  refrescan la UI automáticamente.

### Estructura de `lib/`

| Carpeta | Responsabilidad |
|---|---|
| `core/` | Configuración, tema, inyección de dependencias (`AppServices`), formatos |
| `data/models/` | `Task` (con metadatos de sync), `Session`, `SyncLogEntry` |
| `data/local/` | `AppDatabase` (sqflite), DAOs de tareas, metadatos y bitácora |
| `data/remote/` | `ApiClient` HTTP con token Bearer, timeout y errores tipados |
| `data/security/` | `SecureStore` (flutter_secure_storage) |
| `data/repositories/` | `TaskRepository` (escritura local inmediata), `AuthRepository` |
| `sync/` | `SyncEngine`, `ConflictResolver`, `ConnectivityMonitor`, `SyncCoordinator`, `BackgroundSync` (WorkManager) |
| `ui/` | Pantallas: Login, Tareas, Centro de sincronización, Ajustes |

### Stack (mapeo del temario)

| Capa técnica | Referencia temario | Paquete |
|---|---|---|
| Base de datos local | Room / SQLite | `sqflite` |
| Tareas en segundo plano | WorkManager Android | `workmanager` |
| Monitor de conectividad | ConnectivityManager | `connectivity_plus` |
| Identificadores únicos | UUID / Timestamps | `uuid` |
| Cifrado en reposo | Keystore | `flutter_secure_storage` |

> **Nota de versiones:** la diapositiva sugiere `workmanager ^0.5.2` y `connectivity_plus ^6.0.5`.
> Esas versiones ya no compilan con Flutter 3.4x/AGP 8 (usan el *embedding* v1 de Android),
> por eso se usan `workmanager ^0.10.10` y `connectivity_plus ^7.3.2`, con la misma API
> conceptual (`registerOneOffTask`, `Constraints(networkType: NetworkType.connected)`,
> `onConnectivityChanged`).

---

## 3. Modelo de datos

### 3.1 SQLite (Paso 2)

```sql
CREATE TABLE tasks (
  id           TEXT PRIMARY KEY,        -- UUID v4 generado en el cliente
  title        TEXT NOT NULL,
  description  TEXT NOT NULL DEFAULT '',
  is_completed INTEGER NOT NULL DEFAULT 0,
  is_synced    INTEGER DEFAULT 0,       -- 0 pendiente · 1 sincronizado
  updated_at   TEXT NOT NULL,           -- ISO-8601 UTC para colisiones
  is_deleted   INTEGER DEFAULT 0,       -- borrado lógico (soft delete)
  version      INTEGER NOT NULL DEFAULT 1, -- contador incremental por edición
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_tasks_sync ON tasks(is_synced);

CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT);   -- cursor de PULL, última sync, URL, modo lab
CREATE TABLE sync_log  (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT, level TEXT, source TEXT, message TEXT);
```

* La BD usa `journal_mode=WAL` para que el isolate de WorkManager y la UI no se bloqueen.
* `sync_meta` y `sync_log` viven en SQLite (no en memoria) porque WorkManager los necesita
  con la app cerrada, y para auditar lo que hizo en segundo plano.

### 3.2 Backend

Cada registro del servidor guarda además `owner_uid` (dueño), `server_seq` (contador
monotónico del servidor usado como cursor de PULL) y `last_source` (dispositivo o consola).

| Endpoint | Descripción |
|---|---|
| `POST /auth/register`, `POST /auth/login` | Devuelven `{token, uid, email}` |
| `POST /auth/logout` | Revoca el token |
| `POST /api/tasks/sync` | **PUSH**: lote de cambios → `applied` / `conflict` / `forbidden` por registro |
| `GET /api/tasks?since=<cursor>` | **PULL**: cambios del usuario con `server_seq > cursor` |
| `GET /api/health` | Salud del servicio |
| `/admin/*` | Consola nube (requiere `ADMIN_KEY`) |

---

## 4. Sincronización bidireccional (Paso 6)

| Paso | Qué hace | Dónde |
|---|---|---|
| **01 PUSH** | Envía todos los registros con `is_synced = 0` (incluye borrados lógicos) | `SyncEngine._pushAndAck` |
| **02 ACK** | Marca `is_synced = 1` **solo si la fila sigue en la misma revisión** (`WHERE id=? AND updated_at=? AND version=?`). Si el usuario editó mientras viajaba la petición, la nueva revisión sigue pendiente y no se pierde | `TaskDao.markSynced` |
| **03 PULL** | Descarga cambios remotos desde el cursor `server_seq` (no depende del reloj del teléfono) | `SyncEngine._pullAndMerge` |
| **04 MERGE** | Resuelve cada registro con `ConflictResolver` dentro de una transacción | `ConflictResolver.resolve` |

### ¿Cuándo se sincroniza?

1. **Tras cada escritura local** (con *debounce* de 700 ms para agrupar ráfagas).
2. **Al recuperar la red**: `connectivity_plus` emite el cambio y se ejecuta la cola (Paso 4).
3. **Sin red**: se registra un `OneOffTask` de WorkManager con
   `Constraints(networkType: NetworkType.connected)` → Android lo ejecuta en cuanto haya red,
   **aunque la app esté cerrada** (Paso 5). Si el servidor no responde, devuelve `false` y
   WorkManager reintenta con *backoff* exponencial.
4. **Periódicamente** cada 15 min (mínimo de Android) como respaldo.
5. Al abrir/reanudar la app y con *pull-to-refresh* o el botón de sincronizar.

---

## 5. Resolución de colisiones

> *"¿Cómo resolvemos colisiones de datos cuando la app se utiliza sin conexión y luego se reconecta?"*

Estrategia combinada:

1. **Last-Write-Wins** comparando `updated_at` en **UTC** (prevalece el cambio más reciente).
2. **Control de versiones**: `version` se incrementa en cada edición; desempata marcas
   temporales iguales y permite detectar ediciones concurrentes.

| Situación | Resultado |
|---|---|
| Registro remoto nuevo | Se inserta |
| Local sincronizado, remoto más nuevo | Se sobrescribe (no es colisión) |
| Local **pendiente**, remoto más nuevo | **Colisión → gana la nube** |
| Local **pendiente** más nuevo que el remoto | **Colisión → gana local** y se sube en el siguiente PUSH |
| Misma `updated_at` y `version` | Mismo cambio (eco) → se omite |

El servidor aplica la **misma regla** en el PUSH: si recibe una escritura más vieja que la
que tiene, responde `conflict` con su versión y el cliente la adopta.
Todas las colisiones quedan registradas en la bitácora del **Centro de sincronización**.

---

## 6. Seguridad (Blindaje de datos locales y remotos)

| Requisito | Implementación |
|---|---|
| **Cifrado en reposo** | El token de sesión se guarda con `flutter_secure_storage` (AES con clave en Android Keystore). Nunca en SQLite ni en texto plano |
| **Idempotencia en API** | El ID es un **UUID v4 generado en el cliente**; reenviar un registro (p. ej. si se perdió el ACK) no crea duplicados |
| **Reglas de seguridad** | Toda ruta `/api` exige `Authorization: Bearer`; el UID se toma **del token**, nunca del cuerpo. Un usuario no puede leer ni modificar registros de otro (`forbidden`) |
| **Limpieza de sesión** | Al cerrar sesión: se revoca el token, se cancelan las tareas de WorkManager, se **purga SQLite** y se borran las credenciales cifradas. Advierte si hay cambios sin subir |
| Contraseñas | En el servidor se guardan como `SHA-256(salt + password)` con *salt* aleatorio por usuario |
| Respaldos | `android:allowBackup="false"` para que la BD y las claves no salgan en respaldos |
| Transporte | HTTP solo para el laboratorio local (`usesCleartextTraffic`). En producción: HTTPS |

---

## 7. Escenarios obligatorios de prueba

> Atajo: **Ajustes → Simular sin conexión** equivale a modo avión solo para la app.

### 1. Modo avión
1. Inicia sesión (requiere red la primera vez).
2. Activa el modo avión → aparece el banner ámbar *Sin conexión*.
3. Crea **3 tareas** y edita una → cada una muestra **Pendiente** y el contador *Pendientes sync* = 3.

### 2. Cierre forzado
1. Sin red, cierra la app desde Recientes.
2. Ábrela de nuevo: la sesión se restaura desde el almacenamiento cifrado y las 3 tareas
   siguen ahí (persistencia SQLite).

### 3. Reconexión
1. Desactiva el modo avión.
2. `connectivity_plus` detecta la red → PUSH → ACK → PULL → MERGE automáticamente.
3. En la **Consola Nube** las filas aparecen resaltadas con origen *Dispositivo*.
4. Las tareas cambian a **Sincronizado**.

### Bonus: provocar una colisión
1. Con la app offline, edita la tarea *X*.
2. En la consola, pulsa **Editar en la nube** sobre *X* (es una escritura posterior).
3. Reconecta: la app muestra *"1 colisión resuelta con Last-Write-Wins"* y adopta la versión
   de la nube. (Si editas en la nube **primero** y luego offline, gana la edición del teléfono.)

### Bonus: servidor caído
En la consola, **Simular caída del servidor** (HTTP 503). La app sigue funcionando, registra el
error y WorkManager reintenta con *backoff*.

### Pruebas automatizadas (`flutter test`)
* `conflict_resolver_test.dart`: reglas LWW, desempate por versión, UTC, serialización.
* `sync_engine_test.dart` (SQLite real con `sqflite_common_ffi` + backend falso):
  escenario de 3 registros offline, PULL, colisión gana nube, colisión gana local,
  propagación de borrado lógico, **ACK condicional**, idempotencia y purga de sesión.

---

## 8. Evidencia de nivel de logro

| Dimensión | Evidencia | Dónde |
|---|---|---|
| **Hacer** | App Flutter Offline-First: CRUD con la nube, caché SQLite y sync bidireccional | `offline_first_tasks/`, `cloud_server/` |
| **Saber** | Documentación técnica: modelo de datos, cifrado y reglas backend | Este README (secciones 3–6) |
| **Ser** | Ética y repositorio Git: commits continuos y protección de datos | Purga de sesión, cifrado, `allowBackup=false`, sin secretos en el repo |
