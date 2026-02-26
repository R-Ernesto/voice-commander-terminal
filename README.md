# Voice Commander Terminal

Servicio PowerShell que escucha hotkeys globales e inyecta texto en la ventana activa de Windows Terminal. Diseñado para enviar comandos predefinidos a Claude Code sin escribir.

## Uso rápido

```powershell
# Solo el servicio de shortcuts (para testing)
.\start.ps1 -ServiceOnly

# Servicio + Claude Code (uso real)
.\start.ps1
```

## Shortcuts por defecto

| Hotkey | Acción |
|--------|--------|
| Ctrl+Alt+1 | "Revisa el error y propón una solución" |
| Ctrl+Alt+2 | "Explica este código paso a paso" |
| Ctrl+Alt+3 | "Escribe tests para este módulo" |
| Ctrl+Alt+Q | Detener el servicio |

Editables en `config.json`.

## Arquitectura

```
Windows Terminal (Terminal B)         PowerShell (Terminal A)
┌──────────────────────────┐         ┌──────────────────────────┐
│  Claude Code / shell     │◄────────│  shortcut-service.ps1    │
│  recibe texto pegado     │  paste  │  escucha hotkeys globales│
└──────────────────────────┘         └──────────────────────────┘
                                       │ usa:
                                       ├─ lib/hotkey-listener.ps1
                                       └─ lib/text-injector.ps1
```

**Flujo**:
1. `hotkey-listener.ps1` registra hotkeys globales via Win32 `RegisterHotKey`
2. Al detectar hotkey, captura el handle de la ventana activa (`GetForegroundWindow`)
3. `text-injector.ps1` pone el texto en el clipboard (`Set-Clipboard`)
4. Fuerza foco a la ventana target (`SetForegroundWindow`)
5. Pega via `WScript.Shell SendKeys("^v")`

## Estructura

```
voice-commander-terminal/
├── start.ps1              # Entry point
├── shortcut-service.ps1   # Servicio principal (config + loop + dispatch)
├── config.json            # Shortcuts configurables (hotkey → texto/acción)
├── lib/
│   ├── hotkey-listener.ps1  # Win32 RegisterHotKey + PeekMessage loop
│   └── text-injector.ps1    # Clipboard + SetForegroundWindow + SendKeys paste
├── test-inject.ps1        # Test de diagnóstico (abre Notepad, prueba inyección)
├── ALTERNATIVES.md        # Opciones para escalar (Go, Rust, C#, Electron)
└── service.log            # Log del servicio (gitignored)
```

## Personalizar shortcuts

Editar `config.json`:

```json
{
  "shortcuts": [
    {
      "hotkey": "Ctrl+Alt+5",
      "label": "Mi comando",
      "action": "type",
      "text": "texto que quiero inyectar\n"
    }
  ]
}
```

- `action: "type"` → pega texto en la ventana activa
- `action: "quit"` → detiene el servicio
- `\n` al final del texto → envía Enter automáticamente (ejecuta el comando)
- Teclas soportadas: Ctrl, Alt, Shift, Win + A-Z, 0-9, F1-F12, Space, Enter, Escape, Tab

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
