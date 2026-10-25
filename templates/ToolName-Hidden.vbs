' Optional: start ToolName.bat with no console window. Thin wrapper only; no other logic.
Dim sh, fso, dir
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run """" & dir & "\ToolName.bat""", 0, False
