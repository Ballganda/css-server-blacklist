# Define input and output file paths
$baseDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputFilePath = Join-Path $baseDirectory "ips.txt"   # Path to your IPs input file
$outputFilePath = Join-Path $baseDirectory "server_blacklist.txt" # Output file path

# Get the current Unix timestamp
$currentTimestamp = [int][double]::Parse((Get-Date -UFormat %s))

# Read IPs from the input file
$ips = Get-Content -Path $inputFilePath

# Start building the output content
$blacklistContent = @()
$blacklistContent += '"serverblacklist"'
$blacklistContent += "{"

# Process each IP to format as a server entry
foreach ($ip in $ips) {
    if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') {  # Check if it's a valid IP format
        $blacklistContent += "`t`"server`""
        $blacklistContent += "`t{"
        $blacklistContent += "`t`t`"name`"	`t`t`"ReduceBS $ip`""
        $blacklistContent += "`t`t`"date`"	`t`t`"$currentTimestamp`""
        $blacklistContent += "`t`t`"addr`"	`t`t`"$ip`:0`""  # Ensure IP and port are interpolated correctly
        $blacklistContent += "`t}"
    } else {
        Write-Host "Skipping invalid IP: $ip"
    }
}

$blacklistContent += "}"

# Write the formatted content to the output file
$blacklistContent | Set-Content -Path $outputFilePath -Encoding ASCII

Write-Host "Blacklist file created at $outputFilePath with $($ips.Count) entries."
