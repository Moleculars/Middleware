IF "%MONITOR%" == "" (
    mongo --norc --quiet --eval "db.serverStatus().uptime" && exit 0 || exit 1
) ELSE (
    mongo -u %MONITOR% -p %MONITOR_PASS% --authenticationDatabase "admin" --norc --quiet --eval "db.serverStatus().uptime" && exit 0 || exit 1
)
