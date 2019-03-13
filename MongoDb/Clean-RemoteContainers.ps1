# Pulls the newest images for each given server and removes the current running container
param(
    # servers where mongo image must be updated and current configuration rs container destroyed
    [string[]]$MongoConfigurationHosts = @("D00147"),

    # servers where mongo image must be updated and current shards container destroyed
    [string[]]$MongoShards = @("D00147"),

    # servers where mongo image must be updated and current mongos container destroyed
    [string[]]$Mongos = @("D00147"),

    [string]$MiddlewareTag = "latest",

    # Root for PU images
    [string]$DockerRegistry = "docker.paris.pickup.local"
)

foreach ($hostName in $MongoConfigurationHosts) 
{    
    Invoke-Command -ScriptBlock {
        Write-Progress -ParentId 2 -Activity "Cleaning mongo config rs" -Status "Pulling image on $env:COMPUTERNAME"
        $log = docker pull ${using:DockerRegistry}/pickup/mongodb:${using:MiddlewareTag}
        if (-not $?)
        {
            throw "Docker error [$log]"
        }
        Write-Progress -ParentId 2 -Activity "Installing Mongo Config RS" -Status "Pulling image on $env:COMPUTERNAME" -Completed

        # Remove existing?
        $configCount = @(docker container ls --format '{{ json . }}' | ConvertFrom-Json |? {$_.Names -like "colis21_config_*"}).Count
        if ($configCount -ne 0)
        {
            Write-Progress -Id 1 -Activity "Removing mongo configuration rs" -Status "Removing existing container"
            for ($i = 0; $i -lt $configCount.Count; $i++) 
            {
                $log = docker rm -f "colis21_config_$i"
                if (-not $?)
                {
                    throw "Docker error [$log]"
                }
            }
        }
    } -ComputerName $hostName
}
Write-Progress -Id 1 -Activity "Removing config rs" -Status "Removing existing container" -Completed


foreach ($hostName in $MongoShards) 
{    
    Invoke-Command -ScriptBlock  {
        Write-Progress -ParentId 2 -Activity "Cleaning mongo config rs" -Status "Pulling image on $env:COMPUTERNAME"
        $log = docker pull ${using:DockerRegistry}/pickup/mongodb:${using:MiddlewareTag}
        if (-not $?)
        {
            throw "Docker error [$log]"
        }
        Write-Progress -ParentId 2 -Activity "Installing Mongo Config RS" -Status "Pulling image on $env:COMPUTERNAME" -Completed

        # Remove existing?
        $configCount = @(docker container ls --format '{{ json . }}' | ConvertFrom-Json |? {$_.Names -like "colis21_shard_*"}).Count
        if ($configCount -ne 0)
        {
            Write-Progress -Id 1 -Activity "Removing mongo shard" -Status "Removing existing containers"

            for ($i = 0; $i -lt $configCount.Count; $i++) 
            {
                $log = docker rm -f "colis21_shard_${i}"
                if (-not $?)
                {
                    throw "Docker error [$log]"
                }
            }
            
        }
    } -ComputerName $hostName
}
Write-Progress -Id 1 -Activity "Removing shards" -Status "Removing existing container" -Completed


foreach ($hostName in $Mongos) 
{    
    Invoke-Command -ScriptBlock {
        Write-Progress -ParentId 2 -Activity "Cleaning mongo config rs" -Status "Pulling image on $env:COMPUTERNAME"
        $log = docker pull ${using:DockerRegistry}/pickup/mongodb:${using:MiddlewareTag}
        if (-not $?)
        {
            throw "Docker error [$log]"
        }
        Write-Progress -ParentId 2 -Activity "Installing Mongo Config RS" -Status "Pulling image on $env:COMPUTERNAME" -Completed

        # Remove existing?
        $configCount = @(docker container ls --format '{{ json . }}' | ConvertFrom-Json |? {$_.Names -like "colis21_mongos_*"}).Count
        if ($configCount -ne 0)
        {
            Write-Progress -Id 1 -Activity "Removing mongos" -Status "Removing existing container"
            for ($i = 1; $i -lt $configCount.Count; $i++) 
            {
                $log = docker rm -f "colis21_mongos_$i"
                if (-not $?)
                {
                    throw "Docker error [$log]"
                }
            }
        }
    } -ComputerName $hostName
}
Write-Progress -Id 1 -Activity "Removing mongos" -Status "Removing existing container" -Completed

Write-Output "successfully finished"