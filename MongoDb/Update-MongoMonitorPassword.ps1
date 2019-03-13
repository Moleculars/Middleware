
param(   
    # Set this switch to update user for config rs
    [switch]$UpdateConfigMonitor,

    # Set this switch to update user for shards
    [switch]$UpdateShardMonitor,

    #   Configuration cluster for the sharded cluster. (replica set)
    [string[]]$MongoConfigurationHosts = @("D00206:27017", "D00206:27018", "D00206:27019", "D00206:27020"),
    #   [string[]]$MongoConfigurationHosts = @("srvwp-c21-a1.paris.pickup.local:27017","srvwp-c21-a2.paris.pickup.local:27017","srvwp-c21-a3.paris.pickup.local:27017","srvwp-c21-a4.paris.pickup.local:27017"),    
     
    
    # name of the configs replica set
    [string]$MongoConfigurationRsName = "configRs",

    #  Root user for config rs
    [string]$ConfigAdmin = "root",
    [string]$ConfigAdminPass = "root",

    # User to update for Config rs
    [string]$ConfigMonitor = "monitor",
    [string]$ConfigMonitorPass = "test1",
    
    # mongos 
    [string[]]$Mongos = @("D00206:27025", "D00206:27026"),
    # [string[]]$Mongos = @("srvwp-c21-a1.paris.pickup.local:27019","srvwp-c21-b1.paris.pickup.local:27019","srvwp-c21-b2.paris.pickup.local:27019","srvwp-c21-e1.paris.pickup.local:27019","srvwp-c21-e2.paris.pickup.local:27019","srvwp-c21-d1.paris.pickup.local:27019"),

    # Different sharding servers, each with replicas. Format: ( (shard1_rs1, shard1_rs2, ...), (shard2_rs1, shard2_rs2, ...), ...)
    $MongoShards = @{"c21shard1" = @("D00206:27021", "D00206:27022");
        "c21shard2"              = @("D00206:27023", "D00206:27024")
    },
    #   $MongoShards = @{"c21shard1" = @("srvwp-c21-a1.paris.pickup.local:27018","srvwp-c21-a2.paris.pickup.local:27018");
    #                   "c21shard2" = @("srvwp-c21-a3.paris.pickup.local:27018","srvwp-c21-a4.paris.pickup.local:27018")},

    # local cluster admin for shards 
    [string]$ShardClusterAdmin = "admin",
    [string]$ShardClusterAdminPass = "admin",

    # User to update for shards
    [string]$ShardMonitor = "monitor",
    [string]$ShardMonitorPass = "test2",

    # Docker tag to use for middlewares
    [string]$MiddlewareTag = "latest"
)

# path to keyfile for internal auth in mongo sharded cluster
$keyPath = "C:/data/conf/mongo_keyfile"

# path to db inside container for mongo 
$dbPath = "C:/data/db/"

# image
$mongoImage = "mongo_test:latest"


if ($UpdateConfigMonitor.IsPresent) {

    ###############################################################################
    ## MONGO - CONFIG RS
    ###############################################################################
    Write-Progress -Id 1 -Activity "Updating ${$ConfigMonitor} user for config rs"

    # collections to store names of primary- and secondary
    $configPrimaries = @()
    $configSecondaries = @()

    $i = 0
    foreach ($h in $MongoConfigurationHosts) {  
        $i++
        $hostName = $h.Split(":")[0]
        $mongoPort = [int]$h.Split(":")[1]
        Write-Progress -Id 1 -Activity "Updating Mongo config" -CurrentOperation "Host $hostName port $mongoPort"
        $containerName = "colis21_config_${i}"
        # get result from scriptblock
        $result = Invoke-Command -ScriptBlock {
            
            # If master/primary then update password 
            if ((docker exec ${using:containerName} mongo.exe -u ${using:ConfigAdmin} -p ${using:ConfigAdminPass} --authenticationDatabase "admin" --quiet --eval "db.getSiblingDB('admin').isMaster().ismaster;") -eq $true) {
                Write-Progress -Id 1 -Activity "Updating Monitor pass in primary" -CurrentOperation "Host $hostName port $mongoPort"
                $log = docker exec ${using:containerName} mongo.exe -u ${using:ConfigAdmin} -p ${using:ConfigAdminPass} --authenticationDatabase "admin" --eval "db=db.getSiblingDB('admin').changeUserPassword('${using:ConfigMonitor}','${using:ConfigMonitorPass}');"
                if (-not $?) {
                    throw "Docker error [$log]"
                }
                return $false
            }
            else {
                return $true
            }
        } -ComputerName $hostName

        $config = "$hostName,$mongoPort,$containerName"
        if ($result) {
            $configSecondaries += $config
        }
        else {
            $configPrimaries += $config
        }
    }

    # restart each secondary
    foreach ($secondary in $configSecondaries) {
        
        $hostName = $secondary.Split(",")[0]
        $configPort = $secondary.Split(",")[1]
        $containerName = $secondary.Split(",")[2]
        Write-Progress -Id 1 -Activity "Restarting secondary config replicas: " -Status "secondary $secondary, $configPort, $containerName, $MongoConfigurationRsName"
        Invoke-Command -ScriptBlock {
            
            # stop and wait for death
            $log = docker container rm -f ${using:containerName}
            if (-not $?) {
                throw "Docker error [$log]"
            }
            Start-Sleep -Milliseconds 3000
            
            # now restart the container 
            $log = docker run --restart always -d -p "${using:configPort}`:27017" -v "${using:containerName}`:${using:dbPath}" -e "MONITOR=${using:ConfigMonitor}" -e "MONITOR_PASS=${using:ConfigMonitorPass}" --name "${using:containerName}"  ${using:mongoImage} --keyFile ${using:keyPath} --replSet "${using:MongoConfigurationRsName}" --configsvr --journal --quiet
        
            if (-not $?) {
                throw "Docker error [$log]"
            }

            # wait db ready (this does not use the container healthcheck)
            Start-Sleep -Milliseconds 5000
        } -ComputerName $hostName
    }

    foreach ($configPrimary in $configPrimaries) {
        # stepdown the primary and restart the container
        $hostName = $configPrimary.Split(",")[0]
        $configPort = $configPrimary.Split(",")[1]
        $containerName = $configPrimary.Split(",")[2]
        Write-Progress -Id 1 -Activity "Restarting primary replica: " -Status "primary: $configPort, $containerName, $replicaSetName"
        Invoke-Command -ScriptBlock {
            
            # step down the primary to start a new election
            $log = docker exec "${using:containerName}" mongo.exe -u ${using:ConfigAdmin} -p ${using:ConfigAdminPass} --authenticationDatabase "admin" --quiet --eval "rs.stepDown(60, 300);"
            if (-not $?) {
                throw "Docker error [$log]"
            }
            # wait 3 sec for election to process
            Start-Sleep -Milliseconds 5000

            # stop and wait for death
            $log = docker container rm -f ${using:containerName}
            if (-not $?) {
                throw "Docker error [$log]"
            }
            Start-Sleep -Milliseconds 3000 
            
            # restart the container
            $log = docker run --restart always -d -p "${using:configPort}`:27017" -v "${using:containerName}`:${using:dbPath}" -e "MONITOR=${using:ConfigMonitor}" -e "MONITOR_PASS=${using:ConfigMonitorPass}" --name "${using:containerName}"  ${using:mongoImage} --keyFile ${using:keyPath} --replSet "${using:MongoConfigurationRsName}" --configsvr --journal --quiet
            if (-not $?) {
                throw "Docker error [$log]"
            }
            Write-Progress -Id 1 -Activity "primary replica: restarted" -Status "primary: $configPort, $containerName, $replicaSetName"
            
            # wait db ready (this does not use the container healthcheck)
            Start-Sleep -Milliseconds 3000
            
        } -ComputerName $hostName
    }

    ###############################################################################
    ## MONGOS
    ###############################################################################

    # Simply restarting mongos as the monitor user is found in the config rs
    $configDbUrl = "$MongoConfigurationRsName/" + ($MongoConfigurationHosts -join ',')
    $i = 0
    foreach ($entry in $Mongos) {
        Write-Progress -Id 1 -Activity "Restarting mongos" -Status "Server $entry"
        $i++
        $hostname = $entry.Split(":")[0]
        $port = $entry.Split(":")[1]

        Invoke-Command -ScriptBlock {

            $log = docker container rm -f colis21_mongos_${using:i}
            Start-Sleep -Milliseconds 3000
            if (-not $?) {
                throw "Docker error [$log]"
            }

            $log = docker run -p "${using:port}`:27017" --restart always --name colis21_mongos_${using:i} --hostname mongos -e "MONITOR=${using:ConfigMonitor}" -e "MONITOR_PASS=${using:ConfigMonitorPass}" --entrypoint mongos.exe -d ${using:mongoImage} --keyFile ${using:keyPath} --quiet --bind_ip 0.0.0.0 --configdb ${using:configDbUrl}
            if (-not $?) {
                throw "Docker error [$log]"
            }
            
            # wait db ready (this does not use the container healthcheck)
            Start-Sleep -Milliseconds 3000
        } -ComputerName $hostname
    }

    Write-Progress -Id 1 -Activity "Updated monitor password for Config RS and corresponding mongos" -Completed
}


if ($UpdateShardMonitor.IsPresent) {

    ###############################################################################
    ## MONGO - SHARD
    ###############################################################################
    Write-Progress -Id 2 -Activity "Updating ${$ShardMonitor} user for Shards"

    # collections to store names of primary- and secondary containers
    $shardPrimaries = @()
    $shardSecondaries = @()

    $i = 0

    # Find primary for each shard replica-set and update password on admin db
    foreach ($shardName in $MongoShards.Keys) {
        $shardHosts = $MongoShards[$shardName]

        foreach ($h in $shardHosts) {    
            $i++
            $hostName = $h.Split(":")[0]
            $mongoPort = [int]$h.Split(":")[1]
            Write-Progress -Id 2 -Activity "Updating Mongo shards" -Status "Shard $shardName" -CurrentOperation "Host $hostName port $mongoPort"
            $containerName = "colis21_shard_${i}"
            # get result from scriptblock
            $result = Invoke-Command -ScriptBlock {
                
                # If master/primary then update password 
                if ((docker exec ${using:containerName} mongo.exe -u ${using:ShardClusterAdmin} -p ${using:ShardClusterAdminPass} --authenticationDatabase "admin" --quiet --eval "db.getSiblingDB('admin').isMaster().ismaster;") -eq $true) {
                    Write-Progress -Id 2 -Activity "Updating ${using:ShardMonitor} pass in primary" -Status "Shard ${using:shardName}" -CurrentOperation "Host ${using:hostName} port ${using:mongoPort}"
                    $log = docker exec ${using:containerName} mongo.exe -u ${using:ShardClusterAdmin} -p ${using:ShardClusterAdminPass} --authenticationDatabase "admin" --eval "db=db.getSiblingDB('admin').changeUserPassword('${using:ShardMonitor}','${using:ShardMonitorPass}');"
                    if (-not $?) {
                        throw "Docker error [$log]"
                    }
                    return $false
                }
                else {
                    return $true
                }
            } -ComputerName $hostName

            $shard = "$hostName,$mongoPort,$containerName,$shardName"
            if ($result) {
                $shardSecondaries += $shard
            }
            else {
                $shardPrimaries += $shard
            }
        }
    }

    # restart each secondary
    foreach ($secondary in $shardSecondaries) {
        
        $hostName = $secondary.Split(",")[0]
        $shardPort = $secondary.Split(",")[1]
        $containerName = $secondary.Split(",")[2]
        $replicaSetName = $secondary.Split(",")[3]
        Write-Progress -Id 2 -Activity "Restarting secondary replica: " -Status "secondary $secondary, $shardPort, $containerName, $replicaSetName"
        
        Invoke-Command -ScriptBlock {
            
            # stop and wait for death
            $log = docker container rm -f ${using:containerName}
            Start-Sleep -Milliseconds 3000
            if (-not $?) {
                throw "Docker error [$log]"
            }

            # now restart the container 
            $log = docker run -d -p "${using:shardPort}`:27017" -v "${using:containerName}`:${using:dbPath}" -e "MONITOR=${using:ShardMonitor}" -e "MONITOR_PASS=${using:ShardMonitorPass}" --name "${using:containerName}" ${using:mongoImage} --keyFile ${using:keyPath} --shardsvr --journal --quiet --wiredTigerCacheSizeGB 4 --replSet "${using:replicaSetName}"
            if (-not $?) {
                throw "Docker error [$log]"
            }

            # wait db ready (this does not use the container healthcheck)
            Start-Sleep -Milliseconds 3000
        } -ComputerName $hostName
    }

    # stepdown the primary and restart the container
    foreach ($shardPrimary in $shardPrimaries) {
        $hostName = $shardPrimary.Split(",")[0]
        $shardPort = $shardPrimary.Split(",")[1]
        $containerName = $shardPrimary.Split(",")[2]
        $replicaSetName = $shardPrimary.Split(",")[3]
        Write-Progress -Id 2 -Activity "Restarting primary replica: " -Status "primary: $shardPort, $containerName, $replicaSetName"

        Invoke-Command -ScriptBlock {
            
            # step down the primary to start a new election
            $log = docker exec "${using:containerName}" mongo.exe -u ${using:ShardClusterAdmin} -p ${using:ShardClusterAdminPass} --authenticationDatabase "admin" --quiet --eval "rs.stepDown(60,300);"
            if (-not $?) {
                throw "Docker error [$log]"
            }

            # wait 3 sec for election to process
            Start-Sleep -Milliseconds 3000

            # stop and wait for death
            $log = docker container rm -f ${using:containerName}
            if (-not $?) {
                throw "Docker error [$log]"
            }
            Start-Sleep -Milliseconds 3000 
            
            # restart the container
            $log = docker run -d -p "${using:shardPort}`:27017" -v "${using:containerName}`:${using:dbPath}" -e "MONITOR=${using:ShardMonitor}" -e "MONITOR_PASS=${using:ShardMonitorPass}" --name "${using:containerName}" ${using:mongoImage} --keyFile ${using:keyPath} --shardsvr --journal --quiet --wiredTigerCacheSizeGB 4 --replSet "${using:replicaSetName}"
            if (-not $?) {
                throw "Docker error [$log]"
            }

            # wait db ready (this does not use the container healthcheck)
            Start-Sleep -Milliseconds 3000
            
        } -ComputerName $hostName
    }
    Write-Progress -Id 2 -Activity "Updated monitor password" -Completed
}

Write-Output  "Updated users completed" 