' Starts a PowerShell script without a console window flashing up.
' Usage (scheduled task): wscript.exe run-hidden.vbs "C:\path\script.ps1"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """", 0, False
