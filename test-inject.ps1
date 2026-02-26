# Test rápido: abre Notepad, espera 3 seg, intenta pegar texto.
# Si funciona en Notepad pero no en Terminal, el problema es Windows Terminal.
# Si no funciona en Notepad, el problema es SendKeys/clipboard.

Write-Host "=== Test de inyeccion ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Voy a abrir Notepad y en 3 segundos intentar pegar texto." -ForegroundColor Yellow
Write-Host ""

# Abrir notepad
Start-Process notepad
Start-Sleep -Seconds 3

# Test 1: Clipboard + WScript.Shell
Write-Host "Test 1: Set-Clipboard + WScript.Shell Ctrl+V..." -ForegroundColor DarkGray
Set-Clipboard -Value "TEST-WSCRIPT-OK"
$wsh = New-Object -ComObject WScript.Shell
$wsh.SendKeys("^v")
Start-Sleep -Seconds 1
$wsh.SendKeys("{ENTER}")

# Test 2: WScript.Shell typing directo
Write-Host "Test 2: WScript.Shell SendKeys texto directo..." -ForegroundColor DarkGray
Start-Sleep -Milliseconds 500
$wsh.SendKeys("TEST-DIRECTKEYS-OK")
$wsh.SendKeys("{ENTER}")

Write-Host ""
Write-Host "Revisa Notepad. Deberias ver:" -ForegroundColor Green
Write-Host "  Linea 1: TEST-WSCRIPT-OK    (clipboard + Ctrl+V)" -ForegroundColor White
Write-Host "  Linea 2: TEST-DIRECTKEYS-OK  (SendKeys directo)" -ForegroundColor White
Write-Host ""
Write-Host "Que ves?" -ForegroundColor Yellow
