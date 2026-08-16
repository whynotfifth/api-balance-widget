' Silent launcher for a balance widget (no console window)
' Site name comes from this file name: start-<site>.vbs launches -Site <site>
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
site = Replace(Replace(WScript.ScriptName, "start-", ""), ".vbs", "")
ws.Environment("Process")("WIDGET_NO_CONSOLE") = "1"
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "balance-widget.ps1"" -Site " & site, 0, False