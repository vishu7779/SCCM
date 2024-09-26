<#
Description: This script will help you to determine whether the default Automatic Update service on a machine is managed by SCCM/WSUS or WUfB/Intune based on the service name.
Name:WhoManageUpdates.ps1
#>
#Get the default Automatic Update service
$data = (New-Object -ComObject "Microsoft.Update.ServiceManager").services | Where-Object {$_.IsDefaultAUService -eq $true}
#Check the name of the default Automatic Update service and output the corresponding management tool
if ($data.Name -eq "Windows Server Update Service") {
Write-Host "SCCM/WSUS"
} elseif ($data.Name -eq "Microsoft Update")
{
Write-Host "WUfB/Intune"
}
elseif ($data.Name -eq "Windows Update")
{
Write-Host "Not SCCM or Intune"
} else
{
Write-Host "Unknown update service: $($data.Name)"
}
