# Alternativas de Implementación

El prototipo actual usa PowerShell puro. Estas son las opciones para escalar si se necesita.

## Alternativa A: Go compilado

**Cuándo escalar**: Si PowerShell tiene limitaciones con hotkeys globales o rendimiento.

- Un solo binario `.exe`, sin dependencias
- `golang.design/x/hotkey` para hotkeys globales
- `robotgo` o `keybd_event` para inyección de texto
- Cross-compile posible (aunque este proyecto es solo Windows)
- **Esfuerzo**: ~2-3 horas para migrar

## Alternativa B: Rust TUI (ratatui + crossterm)

**Cuándo escalar**: Si necesitamos un terminal propio con UI personalizada.

- TUI completo con ratatui
- PTY para embeber Claude Code
- Máximo control sobre rendering y input
- `windows-rs` para Win32 APIs nativas
- **Esfuerzo**: ~1-2 días

## Alternativa C: C# / .NET

**Cuándo escalar**: Si necesitamos integración profunda con Windows APIs.

- Mejor soporte nativo para Win32
- Windows Forms para hotkeys nativos (`RegisterHotKey` directo)
- `System.Diagnostics.Process` para manejar Claude Code
- Familiar para ecosistema Windows
- **Esfuerzo**: ~2-3 horas para migrar

## Alternativa D: Electron / Tauri

**Cuándo escalar**: Si necesitamos UI gráfica (paneles, botones, visualización).

- xterm.js embebido para terminal
- Interfaz visual rica con React/Vue
- Tauri preferible a Electron (más ligero, Rust backend)
- **Esfuerzo**: ~2-3 días
- **Riesgo**: Menos estable que las opciones nativas

## Fase futura: Integración de voz

- Reutilizar Whisper STT de voice-commander
- Hotkey `Ctrl+Alt+V` para grabar, transcribir e inyectar texto
- Puede hacerse como módulo adicional en `lib/voice-input.ps1`
- O integrar faster-whisper como sidecar process
