# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

param(
    [Parameter(Mandatory)][int]$TargetPid,
    [Parameter(Mandatory)][string]$ExpectedPath,
    [int]$Seconds = 290
)

Start-Sleep -Seconds $Seconds
$process = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
if ($process -and $process.Path -ieq $ExpectedPath) {
    Stop-Process -Id $TargetPid -Force
}
