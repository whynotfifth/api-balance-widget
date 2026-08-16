' Silent launcher for VibeToken balance widget (no console window)
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
ws.Environment("Process")("WIDGET_NO_CONSOLE") = "1"
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "balance-widget.ps1"" -Site vibetoken", 0, False
