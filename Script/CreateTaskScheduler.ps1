# Define task name and action
$TaskName = "DeleteTempATFiles"
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"Remove-Item 'C:\Users\Temp.AT*' -Force -ErrorAction SilentlyContinue`""

# Define trigger (daily at 2 AM)
$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

# Define principal (SYSTEM account)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create the scheduled task
$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal

# Register the task
Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force
