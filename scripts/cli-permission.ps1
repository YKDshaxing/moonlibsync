param([Parameter(Mandatory=$true)][string]$Directory,
      [Parameter(Mandatory=$true)][string]$Backup,
      [Parameter(Mandatory=$true)][ValidateSet("Deny", "Restore")][string]$Action)
$ErrorActionPreference = 'Stop'
$acl = Get-Acl -LiteralPath $Directory
if ($Action -eq 'Deny') {
  [System.IO.File]::WriteAllText($Backup, $acl.Sddl)
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
  $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $sid, [System.Security.AccessControl.FileSystemRights]::Write, $inherit,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Deny)
  $acl.AddAccessRule($rule)
} else {
  $acl.SetSecurityDescriptorSddlForm([System.IO.File]::ReadAllText($Backup))
}
Set-Acl -LiteralPath $Directory -AclObject $acl
