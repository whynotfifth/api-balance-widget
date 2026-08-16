' Silent launcher for BOTH balance widgets (no console windows)
Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
ws.Run "wscript.exe """ & base & "start-deepseek.vbs""", 0, False
ws.Run "wscript.exe """ & base & "start-vibetoken.vbs""", 0, False
