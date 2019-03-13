
param(
    # Different sharding servers, each with replicas. Format: ( (shard1_rs1, shard1_rs2, ...), (shard2_rs1, shard2_rs2, ...), ...)
    $MongoShards = @{"MyBusinessshard1" = @("D00147:27021", "D00147:27022");
        "MyBusinessshard2"              = @("D00147:27023", "D00147:27024")
    },
    # $MongoShards = @{"MyBusinessshard1" = @("MyBusiness-a1:27018","MyBusiness-a2:27018");
    #                  "MyBusinessshard2" = @("MyBusiness-a3:27018","MyBusiness-a4:27018")},
      

    # Configuration cluster for the sharded cluster. (replica set)
    [string[]]$MongoConfigurationHosts = @("D00147:27017", "D00147:27018", "D00147:27019", "D00147:27020"),
    # [string[]]$MongoConfigurationHosts = @("MyBusiness-a1:27017","MyBusiness-a2:27017","MyBusiness-a3:27017","MyBusiness-a4:27017"),
             
    
    [string]$MongoConfigurationRsName = "MyBusinessConfigRs",
    
    # Where to put mongos
    [string[]]$Mongos = @("D00147:27025", "D00147:27026"),
    # [string[]]$Mongos = @("MyBusiness-a1:27019","MyBusiness-b1:27019","MyBusiness-b2:27019","MyBusiness-e1:27019","MyBusiness-e2:27019","MyBusiness-d1:27019"),

        
    #  Root user for mongos and config rs
    [string]$Root = "root",
    [string]$RootPass = "root",
    
    # read/write for mongos
    [string]$Rw = "rw",
    [string]$RwPass = "rw",
    
    # Monitor user, used for healthchecks
    [string]$MongoMonitor = "monitor",
    [string]$MongoMonitorPass = "monitor",
        
    # local cluster admin for shards 
    [string]$ShardClusterAdmin = "admin",
    [string]$ShardClusterAdminPass = "admin"
)
$ErrorActionPreference = "Stop"
    
# declare vars for mongo
$mongoImage = "windows/mongodb:latest"
$dbPath = "C:/data/db/"
$keyPath = "C:/data/conf/mongo_keyfile"
    
# ###############################################################################
# ## MONGO - CONFIG RS
# ###############################################################################

Write-Progress -Id 2 -Activity "Installing Mongo Config RS"
    
$i = 0
foreach ($h in $MongoConfigurationHosts) {    
    $hostName = $h.Split(":")[0]
    $mongoPort = [int]$h.Split(":")[1]
    $members += @("{_id: $i, host: '$h'}")
    $i++
    Invoke-Command -ScriptBlock {

        # When the keyfile is set a localhost exception is available to create the user admin
        Write-Progress -Id 2 -Activity "Starting container with Keyfile set: MyBusiness_config_${using:i}"
        $log = docker run --restart always -d -p "${using:mongoPort}`:27017" -v "MyBusiness_config_${using:i}`:${using:dbPath}" -e "MONITOR=${using:MongoMonitor}" -e "MONITOR_PASS=${using:MongoMonitorPass}" --name "MyBusiness_config_${using:i}" ${using:mongoImage} --keyFile ${using:keyPath} --replSet "${using:MongoConfigurationRsName}" --configsvr --journal --quiet
                
        if (-not $?) {
            throw "Docker error [$log]"
        }
    
        # wait db ready (this does not use the container healthcheck)
        Start-Sleep -Milliseconds 3000
    
        Write-Progress -Id 2 -Activity "Container successfully created ${i} ${h}"
                
    } -ComputerName $hostName
}

# Cluster them.
$members = $members -join ","
Write-Progress -Id 2 -Activity "Running rs.init() in the first mongo container"
$FirstHost = $MongoConfigurationHosts[0].Split(":")[0]
$FirstMongoPort = $MongoConfigurationHosts[0].Split(":")[1]
Invoke-Command -ScriptBlock {
    $log = docker exec MyBusiness_config_1 mongo --norc --quiet --eval "rs.initiate( {_id: '${using:MongoConfigurationRsName}', configsvr: true, members: [ ${using:members} ]})"
    Write-Progress -Id 2 -Activity "$log"
} -ComputerName $FirstHost
    
###############################################################################
## MONGO - SHARD
###############################################################################

        
# Create and start containers
Write-Progress -Id 2 -Activity "Installing Mongo shards"
$i = 0
foreach ($shardName in $MongoShards.Keys) {
    Write-Progress -Id 2 -Activity "Installing Mongo shards" -Status "Shard $shardName"
            
    # Create all mongod processes for the current shard
    $shardHosts = $MongoShards[$shardName]
    $members = @()
    $hostName = ""
    $mongoPort = ""
    foreach ($h in $shardHosts) {    
        $hostName = $h.Split(":")[0]
        $mongoPort = [int]$h.Split(":")[1]
        $members += @("{_id: $i, host: '$h'}")
        $i++
        Write-Progress -Id 2 -Activity "Installing Mongo shards" -Status "Shard $shardName" -CurrentOperation "Host $hostName port $mongoPort"

        Invoke-Command -ScriptBlock {

            $id = docker run --restart always -d -p "${using:mongoPort}`:27017" -v "MyBusiness_shard_${using:i}`:${using:dbPath}" -e "MONITOR=${using:MongoMonitor}" -e "MONITOR_PASS=${using:MongoMonitorPass}" --name "MyBusiness_shard_${using:i}" ${using:mongoImage} --keyFile ${using:keyPath} --shardsvr --journal --quiet --wiredTigerCacheSizeGB 4 --replSet "${using:shardName}"
            if (-not $?) {
                throw "Docker error [$log]"
            }
    
            # wait db ready (this does not use the container healthcheck)
            Start-Sleep -Milliseconds 3000
                   
        } -ComputerName $hostName
    }
    
    # Cluster the RS shard members
    $members = $members -join ","
    Write-Progress -Id 2 -Activity "initating replica set $hostName : $mongoPort "
    Invoke-Command -ScriptBlock {
        $log = docker exec "MyBusiness_shard_${using:i}" mongo --norc --quiet --eval "rs.initiate( {_id: '${using:shardName}', configsvr: false, members: [ $using:members ]})"
        Write-Progress -Id 2 -Activity "$log"
    } -ComputerName $hostName
}

        
# The vote of a replica set can take up to 10 sec (according to official mongo docs :https://docs.mongodb.com/manual/core/replica-set-elections/)
Start-Sleep -Milliseconds 10000
       
# Create shard-local user admin -> must find primary node (master) in order to create the admin
$x = 0
foreach ($shardName in $MongoShards.Keys) {
    $shardHosts = $MongoShards[$shardName]
    # retrieve members with the n var
    $n = 0 
    foreach ($h in $shardHosts) { 
        $x++
        $hostName = $h.Split(":")[0]
        $mongoPort = [int]$h.Split(":")[1]
                
        Write-Progress -Id 2 -Activity "Adding admin to Mongo shard" -Status "Shard $shardName" -CurrentOperation "Host $hostName port $mongoPort"
                
        Invoke-Command -ScriptBlock {
                    
            $isMaster = docker exec "MyBusiness_shard_${using:x}" mongo.exe --quiet --eval "db.getSiblingDB('admin').isMaster().ismaster;"
            # check if node is primary/master
            if ($isMaster -eq $true) {
                # create local admin for shard replica set
                $log = docker exec "MyBusiness_shard_${using:x}" mongo.exe --quiet --eval "db.getSiblingDB('admin').createUser({user: '${using:ShardClusterAdmin}',pwd: '${using:ShardClusterAdminPass}',roles: [ { role: 'root', db: 'admin' } ]});"
                if (-not $?) {
                    throw "Docker error [$log]"
                }
                Write-Progress -Id 2 -Activity "created admin user for shard ${using:shardName}"
                # create local monitor for healthchecks
                $log = docker exec "MyBusiness_shard_${using:x}" mongo.exe -u ${using:ShardClusterAdmin} -p ${using:ShardClusterAdminPass} --authenticationDatabase "admin" --quiet --eval "db.getSiblingDB('admin').createUser({user: '${using:MongoMonitor}',pwd: '${using:MongoMonitorPass}',roles: [ { role: 'clusterMonitor', db: 'admin' } ]});"
                if (-not $?) {
                    throw "Docker error [$log]"
                }
                Write-Progress -Id 2 -Activity "created monitor user for shard ${using:shardName}"
            }

        } -ComputerName $hostName
        $n++
    }
}
    
        
###############################################################################
## MONGOS
###############################################################################
    
$configDbUrl = "$MongoConfigurationRsName/" + ($MongoConfigurationHosts -join ',')
$i = 0
foreach ($entry in $Mongos) {
    Write-Progress -Id 2 -Activity "Installing mongos" -Status "Server $entry"
    
    $server = $entry.Split(":")[0]
    $mongoPort = if ($entry.Split(":").Count -eq 2) {$entry.Split(":")[1]} else {27019}
    
    if (-not $server -or -not (Test-Connection -Quiet -Count 1 $server)) {
        throw "Cannot contact server [$server]"
    }
    if (-not ($mongoPort -gt 1024 -and $mongoPort -lt 65000)) {
        throw "Invalid port [$mongoPort]"
    }
    $i++
    
    Invoke-Command {    

        Write-Progress -Id 2 -Activity "Installing mongos"  -Status "Server ${using:entry}"  -CurrentOperation "Launching node"
        $log = docker run -d -p "${using:mongoPort}`:27017" --restart always --name MyBusiness_mongos_${using:i} -e "MONITOR=${using:MongoMonitor}" -e "MONITOR_PASS=${using:MongoMonitorPass}" --entrypoint mongos.exe -d ${using:mongoImage} --keyFile ${using:keyPath} --quiet --bind_ip 0.0.0.0 --configdb ${using:configDbUrl}
        if (-not $?) {
            throw "Docker error [$log]"
        }
                
        # wait db ready (this does not use the container healthcheck)
        Start-Sleep -Milliseconds 3000

    } -ComputerName $server
    
    Write-Progress -Id 2 -Activity "Installing mongos completed"
}
    
# get first mongos
$firstMongos = $Mongos[0].Split(":")[0]
    
# Connect to a mongos instance and create admin plus other users
Invoke-Command -ScriptBlock {
    param([hashtable]$shards)
    
    Write-Progress -Id 2 -Activity "Adding users to mongos ${using:firstMongos}"
    
    $id = "MyBusiness_mongos_1"
    
    # create admin in container and stop mongo server and remove tmp container automatically
    $log = docker exec $id mongo.exe --eval "db.getSiblingDB('admin').createUser({user: '${using:Root}',pwd: '${using:RootPass}',roles: [ { role: 'root', db: 'admin' } ]});"
    if (-not $?) {
        throw "Docker error [$log]"
    }
    Write-Progress -Id 2 -Activity "$log"
    
    $createUsersCmd = "db=db.getSiblingDB('admin');db.createUser({user: '${using:Rw}',pwd: '$using:RwPass',roles: [ { role: 'readWrite', db: 'MyBusiness_events'} ]});db.getSiblingDB('admin').createUser({user: '${using:MongoMonitor}',pwd: '${using:MongoMonitorPass}',roles: [ { role: 'clusterMonitor', db: 'admin' } ]});"
    # connect again with admin, and create other users
    $log = docker exec $id mongo.exe -u ${using:Root} -p ${using:RootPass} --authenticationDatabase "admin" --eval "$createUsersCmd"
    if (-not $?) {
        throw "Docker error [$log]"
    }
    Write-Progress -Id 2 -Activity "$log"
    
    # Reference the shards in the configuration database and create MyBusiness collections
    Write-Progress -Id 2 -Activity "Creating mongo shard collections"
    foreach ($shard in $shards.Keys) {
        $shardName = $shard
        $shardHosts = ${shards}[$shard]
        $shardUrl = "${shardName}/" + ($shardHosts -join ',')
        $log = docker exec $id mongo.exe -u ${using:Root} -p ${using:RootPass} --authenticationDatabase "admin" --norc --quiet --eval "sh.addShard('$shardUrl')"
        if (-not $?) {
            throw "Docker error [$log]"
        }
        Write-Progress -Id 2 -Activity "$log"
    }
    
    # finally enable sharding for the db's
    $shardCommand = "sh.enableSharding('MyBusiness_events');sh.shardCollection('MyBusiness_events.parcels', {ParcelCarrierId: 'hashed'}, false, {numInitialChunks: 30});sh.shardCollection('MyBusiness_events.analysis', {ParcelId: 'hashed'}, false, {numInitialChunks: 30});sh.shardCollection('MyBusiness_events.rejections', {_id: 'hashed'}, false, {numInitialChunks: 30});"
    $log = docker exec $id mongo.exe -u ${using:Root} -p ${using:RootPass} --authenticationDatabase "admin" --norc --quiet --eval "$shardCommand"
    Write-Progress -Id 2 -Activity "$log"
        
} -ComputerName $firstMongos -ArgumentList $MongoShards
    
Write-Progress -Id 2 -Activity "Configured Mongo with sharded cluster completed" -Completed
Write-Output  "Configured MongoDb with sharded cluster completed"    
            