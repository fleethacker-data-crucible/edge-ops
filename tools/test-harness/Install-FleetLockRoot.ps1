<#
.SYNOPSIS
    One-time (elevated) setup: creates C:\ProgramData\fleethacker\locks and grants BUILTIN\Users Modify.
#>
Set-StrictMode -Version Latest
$root = Join-Path $env:ProgramData 'fleethacker\locks'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$acl = Get-Acl -LiteralPath $root
$sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $root -AclObject $acl
Get-Acl -LiteralPath $root | Select-Object -ExpandProperty Access | Format-Table IdentityReference, FileSystemRights, IsInherited -AutoSize
