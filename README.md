# Voice Commander Terminal

Servicio PowerShell + sidecar Python que inyecta texto en la ventana activa de Windows Terminal via hotkeys globales y entrada por voz. Diseñado para interactuar con Claude Code sin escribir.

## Uso rápido

```powershell
# Solo el servicio (shortcuts + voz, sin Claude Code)
.\start.ps1 -ServiceOnly

# Servicio + Claude Code (uso real)
.\start.ps1

# Desde cualquier terminal (shortcut de PowerShell profile)
voice-sidecar
```

## Hotkeys

### Texto predefinido — frases frecuentes al instante

Atajos para prompts que usas repetidamente con Claude Code. Un solo atajo manda la frase completa sin tener que dictarla ni escribirla cada vez.

| Hotkey | Texto |
|--------|-------|
| Ctrl+Alt+1 | "Revisa el error y propón una solución" + Enter |
| Ctrl+Alt+2 | "Explica este código paso a paso" + Enter |
| Ctrl+Alt+3 | "Escribe tests para este módulo" + Enter |
| Ctrl+Alt+Q | Detener el servicio |

Editables en `config.json`. Puedes agregar más frases que uses seguido.

### Voz — push-to-talk con Whisper STT

Mantén presionado el hotkey mientras hablas, suelta para transcribir e inyectar.

| Hotkey | Modo | Descripción |
|--------|------|-------------|
| Ctrl+Alt+V | **Submit** | Graba → transcribe → pega texto → **Enter** (se envía a Claude automáticamente) |
| Ctrl+Alt+T | **Texto** | Graba → transcribe → pega texto → **sin Enter** (puedes revisar/editar antes de enviar) |

**Cuándo usar cada uno:**
- **Ctrl+Alt+V** — cuando sabes lo que quieres decir y quieres que Claude lo procese directo. Ej: "explica qué hace esta función", "arregla el error de conexión".
- **Ctrl+Alt+T** — cuando quieres dictar algo largo o complejo y revisar antes de enviarlo. Ej: dictar una descripción de un bug, redactar un mensaje, o cuando no estás seguro de que Whisper transcribirá bien.

## Arquitectura

```
 Hotkeys de texto (Ctrl+Alt+1/2/3)     Hotkeys de voz (Ctrl+Alt+V / T)
        │                                       │
        ▼                                       ▼
 [PS shortcut-service]                   [Python sidecar]
  RegisterHotKey                          keyboard lib (push-to-talk)
  PeekMessage loop ◄──── poll 50ms ────  signal.json (atómico)
        │                                       │
        ▼                                       ▼
 [PS text-injector]                      [faster-whisper STT]
  SetForegroundWindow                     CUDA / float16
  Clipboard + SendKeys paste              Modelo: medium
        │
        ▼
 [Ventana target]
  Claude Code / shell / cualquier app
```

**Flujo de texto predefinido**:
1. PS `RegisterHotKey` detecta el atajo
2. Captura `GetForegroundWindow()` inmediatamente
3. `Set-Clipboard` + `SendKeys("^v")` pega el texto

**Flujo de voz**:
1. Python detecta key-down → captura hwnd → beep 800Hz → graba audio
2. Key-up → beep 600Hz → Whisper transcribe → escribe `signal.json`
3. PS poll detecta el archivo → `SetForegroundWindow(hwnd)` → clipboard paste

## Estructura

```
voice-commander-terminal/
├── start.ps1               # Entry point (lanza service + sidecar + claude)
├── shortcut-service.ps1    # Servicio PS (hotkeys + poll de signal.json)
├── config.json             # Shortcuts + config de voz (modelo Whisper, hotkeys)
├── lib/
│   ├── hotkey-listener.ps1 # Win32 RegisterHotKey + PeekMessage loop
│   ├── text-injector.ps1   # Clipboard + SetForegroundWindow + SendKeys paste
│   └── voice-poll.ps1      # Polling de signal.json
├── sidecar/
│   ├── voice_sidecar.py    # Entry point Python (config + warmup + loop)
│   ├── hotkey_handler.py   # Push-to-talk (key-down/up + captura hwnd)
│   ├── audio_recorder.py   # Captura audio (sounddevice InputStream)
│   ├── stt.py              # Wrapper faster-whisper (singleton)
│   ├── signal_writer.py    # Escritura atómica signal.json
│   └── requirements.txt    # Deps Python (referencia, usa venv de voice-commander)
├── test-inject.ps1         # Test de diagnóstico (abre Notepad, prueba inyección)
├── ALTERNATIVES.md         # Opciones para escalar (Go, Rust, C#, Electron)
└── service.log             # Log del servicio (gitignored)
```

## Personalizar

### Agregar shortcuts de texto

Editar `config.json` → sección `shortcuts`:

```json
{
  "hotkey": "Ctrl+Alt+5",
  "label": "Mi comando",
  "action": "type",
  "text": "texto que quiero inyectar\n"
}
```

- `\n` al final → envía Enter automáticamente
- Teclas soportadas: Ctrl, Alt, Shift, Win + A-Z, 0-9, F1-F12, Space, Enter, Escape, Tab

### Configurar voz

Editar `config.json` → sección `voice`:

```json
"voice": {
  "hotkey": "ctrl+alt+v",
  "hotkey_text": "ctrl+alt+t",
  "whisper_model": "medium",
  "whisper_device": "cuda",
  "whisper_compute_type": "float16",
  "whisper_initial_prompt": "KAPS, Syion, Claude Code, PowerShell, git"
}
```

- `whisper_initial_prompt` — palabras que Whisper debe reconocer (nombres propios, técnicos). **Se recarga en caliente**: edita el prompt y la próxima grabación ya lo usa, sin relanzar el sidecar.
- `whisper_model` — `tiny`, `base`, `small`, `medium`, `large-v3` (más grande = más preciso, más lento). Cambiar modelo **sí requiere relanzar**.
- Requiere venv de `voice-commander` (`C:\dev\my-adventures\voice-commander\.venv`) con faster-whisper + CUDA. No tiene venv propio, reutiliza el existente.

## Diagnóstico

Si los shortcuts no inyectan texto:

```powershell
# 1. Verificar que el mecanismo de inyección funciona
.\test-inject.ps1
# Abre Notepad y prueba SendKeys. Si aparece texto → el problema no es SendKeys.

# 2. Revisar el log
cat .\service.log
# Muestra hotkeys detectados, ventana target, errores.
```

## Struggles y soluciones (dev log)

### 1. Start-Job no puede inyectar texto
**Problema**: `Start-Job` crea un proceso PowerShell en sesión no-interactiva. Este proceso no tiene acceso al input desktop de Windows, por lo que `SendInput` y `SendKeys` fallan silenciosamente.

**Solución**: No usar `Start-Job`. Con `-ServiceOnly` el servicio corre directo en el proceso actual (interactivo). En modo normal, se lanza como `Start-Process powershell -WindowStyle Minimized` (proceso separado con ventana propia = acceso al desktop).

### 2. SendInput unicode no funciona con Windows Terminal
**Problema**: El primer approach enviaba cada carácter via Win32 `SendInput` con `KEYEVENTF_UNICODE`. Funcionaba en Notepad pero Windows Terminal lo ignoraba silenciosamente. WT usa DirectX para rendering/input y no procesa eventos de teclado sintéticos de SendInput de la misma forma.

**Solución**: Cambiar a clipboard paste. `Set-Clipboard` + `WScript.Shell SendKeys("^v")` funciona porque Ctrl+V es un shortcut que Windows Terminal sí procesa nativamente.

### 3. System.Windows.Forms.Clipboard falla en PowerShell 7
**Problema**: `[System.Windows.Forms.Clipboard]::SetText()` requiere modo STA (Single-Threaded Apartment). PowerShell 7 corre en MTA por defecto. El clipboard se seteaba silenciosamente mal (sin error, sin texto).

**Solución**: Usar `Set-Clipboard` / `Get-Clipboard` que son cmdlets nativos de PowerShell y manejan el threading internamente.

### 4. El texto se pegaba en la ventana equivocada
**Problema**: Al procesar el hotkey, el foco podía cambiar entre el momento de detección y el momento de paste (200ms de delay para soltar modifier keys). El texto terminaba pegándose en la terminal del servicio en vez de la terminal target.

**Solución**: Capturar `GetForegroundWindow()` inmediatamente al detectar el hotkey (antes de cualquier delay). Luego usar `SetForegroundWindow(handle)` para forzar el foco de vuelta a la ventana correcta antes de pegar.

### 5. Add-Type falla al re-ejecutar en la misma sesión
**Problema**: Si ejecutas el script, lo modificas, y lo ejecutas de nuevo en la misma sesión de PowerShell, `Add-Type` falla porque el tipo C# ya está cargado en el AppDomain y no se puede redefinir.

**Solución**: Guard con `if (-not ([System.Management.Automation.PSTypeName]'TypeName').Type)` antes de cada `Add-Type`. Igualmente, abrir una terminal nueva si se cambia la definición del tipo.

### 6. Ctrl+Alt+V/T produce caracteres ^V / ^T en la terminal
**Problema**: La lib `keyboard` de Python escuchaba los hotkeys con `on_press_key(suppress=False)`, dejando que las teclas llegaran a la terminal. En Windows, Ctrl+Alt equivale a AltGr, produciendo caracteres especiales (`^V`, `^T`) antes del texto transcrito.

**Solución**: Cambiar a `keyboard.add_hotkey(combo, callback, suppress=True)` que intercepta el combo completo y lo consume antes de que llegue a la terminal. El key-up no necesita suppress porque no genera caracteres.
