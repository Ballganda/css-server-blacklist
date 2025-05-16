# Define the parameters for the script
param (
    #[Parameter(Mandatory=$true)]
    [int]$appid = 240,         # Require appid input 
	[int]$BSLimit = 30,     # Default value for duplicate BS threshold
    [int]$mplayer = 66   # Default value for max players threshold
)
Write-Host "ReduceBS running with these parameters"
Write-Host "appid   : $appid. The Steam appid"
Write-Host "BSLimit : $BSLimit. Threshold Number of servers on one IP to flag as BS"
Write-Host "mplayer : $mplayer. Threshold max_player limit to flag as BS"
Write-Host "Customize search with flags. Example -appid 10 -BSLimit 30 -mplayer 32"

# Define relative paths for input and output directories
$baseDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDirectory = Join-Path $baseDirectory "data"
$outputDirectory = Join-Path $baseDirectory "output"

# Get the current Unix timestamp
$currentTimestamp = [int][double]::Parse((Get-Date -UFormat %s))

# Set paths for inputs output files
$apiKeyFile = Join-Path $dataDirectory "steamwebapikey.txt"
$filterFile = Join-Path $dataDirectory "appid$appid-filters.txt"
$blacklistFile = Join-Path $dataDirectory "appid$appid-blacklist.txt"

# Get the latest file with UNIX timestamp in the output directory (if it exists)
$preOutputIPFile = Get-ChildItem -Path $outputDirectory -Filter "appid$appid-rbs-ip-*.txt" |
                   Sort-Object LastWriteTime -Descending |
				   Select-Object -First 1

if ($preOutputIPFile) {
    $preOutputIPFile = $preOutputIPFile.FullName
} else {
    Write-Host "No previous output file found."
    $preOutputIPFile = $null
}
# Set paths for output files
$outputIPFile = Join-Path $outputDirectory "appid$appid-rbs-ip-$currentTimestamp.txt"
$combinedOutputFile = Join-Path $outputDirectory "appid$appid-rbs-$currentTimestamp.json"

# Ensure output directory exists
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Main script logic
function Run-Main {
	
	
	# Read API key and filters
	Write-Host "Reading API Key File : $apiKeyFile"
	$apiKey = Read-ApiKey -apiKeyFile $apiKeyFile
	Write-Host "Reading Filter File : $filterFile"
	Write-Host "Reading Blacklist File : $blacklistFile"
	$filterData = Read-FilterFiles -filterFile $filterFile # -blacklistFile $blacklistFile -preOutputIPFile $preOutputIPFile
	$filters = $filterData.filters # Extract filters array from hashtable

	# Base filter with appid and secure
	$baseFilter = "\appid\$appid"
	Write-Host "Set base APPID filter : $baseFilter"

	# Download server data
	Write-Host "Starting download of server lists for : $baseFilter"
	$servers = Download-Servers -apiKey $apiKey -filters $filters -baseFilter $baseFilter

	# Call the function to remove duplicates and count IPs
	$processedData = Remove-Duplicates-And-Count-IP -servers $servers
	$uniqueServers = $processedData.UniqueServers
	$ipCountTable = $processedData.IpCountTable

	# Call the function to add properties to the unique servers
	$processedServers = Add-Properties-To-Servers -uniqueServers $uniqueServers -ipCountTable $ipCountTable -BSLimit $BSLimit -mplayer $mplayer

	# Save flagged IPs to file
	Save-Flagged-IPs -servers $processedServers -outputFile $outputIPFile -preOutputIPFile $preOutputIPFile -blacklistFile $blacklistFile

	# Save processed server data to file
	Save-Processed-Servers -servers $processedServers -outputFile $combinedOutputFile

	Write-Host "All tasks completed successfully."
}

# Function to read API key from a file
function Read-ApiKey {
    param (
        [string]$apiKeyFile
    )
    
    if (Test-Path $apiKeyFile) {
        return (Get-Content -Path $apiKeyFile -Raw).Trim()
    } else {
        throw "API key file not found: $apiKeyFile"
    }
}

# Function to read and print filters from multiple specified files
function Read-FilterFiles {
    param (
        [string]$filterFile
        #[string]$blacklistFile,
        #[string]$preOutputIPFile
    )

    # Initialize an empty array to collect all filters
    $allFilters = @()

    # Define an array of file paths to check
    $filterFiles = @($filterFile) #, $blacklistFile, $preOutputIPFile)

    foreach ($file in $filterFiles) {
        # Check if the file variable is not null or empty and the file exists
        if (![string]::IsNullOrWhiteSpace($file) -and (Test-Path $file)) {
            $allFilters += Process-Filters -Path $file
        }
    }

    # Remove duplicates
    $uniqueFilters = $allFilters | Sort-Object -Unique

    return @{ filters = $uniqueFilters }
	#return $uniqueFilters
}

# Function to read filters from a file and process them (handles IP addresses and general filters)
function Process-Filters {
    param (
        [string]$Path
    )
    
    if (Test-Path $Path) {
        # Read and process filters from the file
        $filters = (Get-Content -Path $Path -Raw -ErrorAction Stop) -split "`r`n" | Where-Object { $_ -ne "" }

        # Regex pattern to check for valid IP addresses
        $ipRegex = '^\d{1,3}(\.\d{1,3}){3}$'

        # Modify only IP addresses by adding "\addr\" prefix
        return $filters | ForEach-Object {
            if ($_ -match $ipRegex) {
                "\addr\$($_)" # Add prefix if it's an IP
            } else {
                $_ # Leave general filters unchanged
            }
        }
    } else {
        return @() # Return empty array if the file doesn't exist
    }
}

# Function to download servers based on filters with parallel jobs and throttling
function Download-Servers {
    param (
        [string]$apiKey,
        [array]$filters,
        [string]$baseFilter
    )

    # Array to hold jobs
    $jobs = @()
    $totalFilters = $filters.Count
    $currentFilterIndex = 0
    $progressBatchSize = 1
    $jobLimit = 300  # Define a limit for concurrent jobs

    foreach ($filter in $filters) {
        $currentFilterIndex++
        $combinedFilter = "$baseFilter$filter"

        # Progress update
        if ($currentFilterIndex % $progressBatchSize -eq 0) {
            $percentComplete = ($currentFilterIndex / $totalFilters) * 100
            Write-Progress -Activity "Starting Server List Downloads" `
                           -Status "Processing filter $currentFilterIndex of $totalFilters $combinedFilter" `
                           -PercentComplete $percentComplete
        }

        # Throttle the number of parallel jobs
        while ($jobs.Count -ge $jobLimit) {
            Start-Sleep -Milliseconds 500
            $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
        }

        # Start parallel job for each filter
        $jobs += Start-Job -ScriptBlock {
            param($apiKey, $combinedFilter)
            $messages = @()

            $url = "https://api.steampowered.com/IGameServersService/GetServerList/v1/?key=$apiKey&limit=50000&filter=$combinedFilter"
            try {
                $jsonData = Invoke-RestMethod -Uri $url
                if (!$jsonData.response.servers) {
                    $messages += "No servers found for filter: '$combinedFilter'"
                    return [PSCustomObject]@{ Servers = $null; Messages = $messages }
                } else {
                    return [PSCustomObject]@{ Servers = $jsonData.response.servers; Messages = $messages }
                }
            } catch [System.Net.WebException] {
                $messages += "WebException for filter '$combinedFilter': $_.Exception.Message"
                return [PSCustomObject]@{ Servers = $null; Messages = $messages }
            } catch {
                $messages += "Error downloading data for filter '$combinedFilter': $_"
                return [PSCustomObject]@{ Servers = $null; Messages = $messages }
            }

        } -ArgumentList $apiKey, $combinedFilter
    }
    Write-Progress -Activity "Starting Server List Downloads" -Status "Completed" -PercentComplete 100 -Completed
    
	# Wait for all jobs to finish
	$servers = @()
	$totalJobs = $jobs.Count
	$completedJobs = 0

	# Wait for all jobs to complete before retrieving results
	while ($jobs | Where-Object { $_.State -eq 'Running' }) {
		foreach ($spinner in '|', '/', '-', '\') {
		Write-Host -NoNewline "Waiting for all jobs to complete...[$spinner]PLEASE STAND BY[$spinner]...`r"
		Start-Sleep -Milliseconds 250
		}
	}
	Write-Host "All jobs have completed downloading."

	Write-Host "Combining results from completed jobs..."
	# Retrieve results from all completed jobs in one pass
	foreach ($job in $jobs) {
		$completedJobs++
		$result = Receive-Job -Job $job

		# Update progress for combining results
		$percentComplete = ($completedJobs / $totalJobs) * 100
		Write-Progress -Activity "Combining Results" `
					   -Status "Processing job $completedJobs of $totalJobs" `
					   -PercentComplete $percentComplete

		# Skip if no result is returned
		if (-not $result) {
			continue
		}

		# Output any messages from the job
		foreach ($message in $result.Messages) {
			Write-Host $message
		}

		# Collect servers if present
		if ($result.Servers) {
			$servers += $result.Servers
		}
	}

	# Final progress update after all jobs are processed
	Write-Progress -Activity "Combining Results" -Status "Completed" -PercentComplete 100 -Completed

    # Clean up jobs
	Remove-Job -Job $jobs

	Write-Host "All results have been combined successfully."
	return $servers

}

# Function to remove duplicates and count IP occurrences
function Remove-Duplicates-And-Count-IP {
    param (
        [array]$servers
    )

    # Define batch size for progress updates
    $progressBatchSize = 500
	
    $ipCountTable = [hashtable]::Synchronized(@{})     # Tracks the number of times each IP address appears (duplicates count)
    $uniqueServersWithPort = [hashtable]::Synchronized(@{}) # Stores unique servers with exact IP:PORT match
    $uniqueServers = [hashtable]::Synchronized(@{})    # Stores unique servers with IP (without port) for IP counting
    $totalServers = $servers.Count
    $currentIndex = 0
	
	Write-Host "Total servers found with dupes: $totalServers"

    # Process servers to first remove duplicates with exact IP:PORT match
    foreach ($server in $servers) {
        $currentIndex++

        # Only update progress every 500 iterations to minimize Write-Progress overhead
        if ($currentIndex % $progressBatchSize -eq 0) {
            $percentComplete = ($currentIndex / $totalServers) * 100
            Write-Progress -Activity "Removing Duplicates and Counting IPs" `
                           -Status "Processed $currentIndex of $totalServers servers" `
                           -PercentComplete $percentComplete
        }

        $ipWithPort = $server.addr     # Exact IP:PORT address
        $ipAddress = $server.addr -replace ':\d+$', '' # Strip port for IP counting

        # Skip if the server with IP:PORT already exists
        if ($uniqueServersWithPort.ContainsKey($ipWithPort)) {
            continue
        }

        # Keep only one instance of each unique IP:PORT address
        $uniqueServersWithPort[$ipWithPort] = $server

        # Count IP occurrences (used later for rbsipcnt, ignoring the port)
        $ipCountTable[$ipAddress] = ($ipCountTable[$ipAddress] + 1)
		
		# If the server exists, compare max_players and keep the larger value
		if ($uniqueServers[$ipAddress]) {
			$uniqueServers[$ipAddress].max_players = [Math]::Max($uniqueServers[$ipAddress].max_players, $server.max_players)
		} else {
			# If it doesn't exist, add the server to uniqueServers
			$uniqueServers[$ipAddress] = $server
		}
		
    }

    # Final Write-Progress update after loop ends
    Write-Progress -Activity "Removing Duplicates and Counting IPs" -Status "Completed" -PercentComplete 100 -Completed

    # Return both the unique servers and the IP count table for further processing
    return @{
        UniqueServers = $uniqueServers.Values;    # Servers with unique IP (without port)
        IpCountTable  = $ipCountTable             # IP count table (ignores port)
    }
}

# Function to add properties (rbsipcnt, rbsactive, rbsflagged)
function Add-Properties-To-Servers {
    param (
        [array]$uniqueServers,
        [hashtable]$ipCountTable,
        [int]$BSLimit,      # Default threshold for duplicates
        [int]$mplayer    # Default threshold for max players
    )

    # Define batch size for progress updates
    $progressBatchSize = 5
    $totalUniqueServers = $uniqueServers.Count
    $currentIndex = 0
	
    Write-Host "Total unique server IPs found: $totalUniqueServers"
    Write-Progress -Activity "Adding Properties" -Status "Starting..." -PercentComplete 0

    # Add rbsipcnt, rbsflagged, and rbsactive properties
    foreach ($server in $uniqueServers) {
        $currentIndex++
        $percentComplete = ($currentIndex / $totalUniqueServers) * 100

        if ($currentIndex % $progressBatchSize -eq 0) {
            Write-Progress -Activity "Adding Properties" `
                           -Status "Setting properties for server $currentIndex of $totalUniqueServers" `
                           -PercentComplete $percentComplete
        }

		# Ensure the server has the properties, add them if missing
		$server | Add-Member -MemberType NoteProperty -Name "rbsIP" -Value NULL -Force
		$server | Add-Member -MemberType NoteProperty -Name "rbsIPcnt" -Value 0 -Force
		$server | Add-Member -MemberType NoteProperty -Name "rbsFlagged" -Value 0 -Force
		$server | Add-Member -MemberType NoteProperty -Name "rbsActive" -Value 0 -Force
		$server | Add-Member -MemberType NoteProperty -Name "rbsReason" -Value "" -Force

		# Set rbsIP and rbsIPcnt based on how many times the IP address occurred
		$ipAddress = $server.addr -replace ':\d+$', '' # Strip port for IP
		$server.rbsIP = $ipAddress
		$server.rbsIPcnt = $ipCountTable[$ipAddress]

		# Set flagging based on conditions (BS Threshold and maxPlayerThreshold)
		if ($server.rbsIPcnt -gt $BSLimit) {
			$server.rbsFlagged = 1
			$server.rbsActive = 1
			$server.rbsReason += "BS$BSLimit+"
		}

		if ($server.max_players -gt $mplayer) {
			$server.rbsFlagged = 1
			$server.rbsActive = 1
			# If rbsReason already has content, prepend with a comma and space
			if ($server.rbsReason -ne "") {
				$server.rbsReason += ", "
			}
			$server.rbsReason += "max_players $mplayer+"
		}

    }

    Write-Progress -Activity "Adding Properties" -Status "Completed" -PercentComplete 100 -Completed

    return $uniqueServers
}

# Function to save flagged IPs to file
function Save-Flagged-IPs {
    param (
        [array]$servers,
        [string]$outputFile,
        [string]$preOutputIPFile,  # Path to the previous output file
		[string]$blacklistFile
    )

    $flaggedServers = $servers | Where-Object { $_.rbsflagged -eq 1 }
    $totalServers = $flaggedServers.Count
    $currentIndex = 0
    $flaggedIPs = @()

    # Collect the flagged IPs from current servers
    foreach ($server in $flaggedServers) {
        $currentIndex++
        $percentComplete = ($currentIndex / $totalServers) * 100
        Write-Progress -Activity "Saving Flagged IPs" -Status "Processing IP $currentIndex of $totalServers" -PercentComplete $percentComplete

        $flaggedIPs += $server.rbsIP
    }

    # If previous output file exists, read its content
    if (Test-Path $preOutputIPFile) {
        Write-Host "Loading previous flagged IPs from $preOutputIPFile"
        $previousIPs = Get-Content -Path $preOutputIPFile
        $flaggedIPs += $previousIPs  # Append previous IPs to the current list
    }
	
	# If previous output file exists, read its content
    if (Test-Path $blacklistFile) {
        Write-Host "Loading previous flagged IPs from $blacklistFile"
        $blacklistIPs = Get-Content -Path $blacklistFile
        $flaggedIPs += $blacklistIPs  # Append previous IPs to the current list
    }
	
    # Remove duplicates and sort the flagged IPs
    $sortedFlaggedIPs = $flaggedIPs | Sort-Object {
        # Split the IP into segments and convert to integers for correct sorting
        $segments = $_ -split '\.'
        [int]$segments[0] * 16777216 + [int]$segments[1] * 65536 + [int]$segments[2] * 256 + [int]$segments[3]
    } | Select-Object -Unique  # Remove duplicates

    # Save the sorted flagged IPs to the output file
    $sortedFlaggedIPs | Set-Content -Path $outputFile
    Write-Progress -Activity "Saving Flagged IPs" -Status "Completed" -PercentComplete 100 -Completed
    Write-Host "Flagged IPs saved to $outputFile"
}

# Function to save processed server data to file
function Save-Processed-Servers {
    param (
        [array]$servers,
        [string]$outputFile
    )

    Write-Progress -Activity "Saving Processed Servers" -Status "Saving processed data" -PercentComplete 0
    $finalOutput = @{ response = @{ servers = $servers } }
    $finalOutput | ConvertTo-Json -Depth 3 | Set-Content -Path $outputFile
    Write-Progress -Activity "Saving Processed Servers" -Status "Completed" -PercentComplete 100 -Completed
    Write-Host "Processed server data saved to $outputFile"
}

# Call main script function after defining all functions
Run-Main