' Config wizard for the balance widget (no console window)
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
ws.Environment("Process")("WIDGET_NO_CONSOLE") = "1"
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "setup.ps1""", 0, False
