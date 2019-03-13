@echo off

(
echo {
echo  "users": [
echo  {
echo    "name": "guest",
echo    "password": "IdontWantToBeUsedPlease_11:!",
echo    "tags": ""
echo  },
echo  {
echo   "name": "%ADMIN_USER%",
echo   "password": "%ADMIN_PASS%",
echo   "tags": "administrator"
echo  },
echo  {
echo   "name": "%RW_USER%",
echo   "password": "%RW_USER_PASS%",
echo   "tags": "policymaker"
echo  },
echo  {
echo   "name": "%RO_USER%",
echo   "password": "%RO_USER_PASS%",
echo   "tags": "management"
echo  }
echo  ],
echo  "vhosts": [
echo  {
echo   "name": "\/"
echo  }
echo  ],
echo  "permissions": [
echo  {
echo   "user": "%ADMIN_USER%",
echo   "vhost": "\/",
echo   "configure": ".*",
echo   "write": ".*",
echo   "read": ".*"
echo  },
echo  {
echo   "user": "%RW_USER%",
echo   "vhost": "\/",
echo   "configure": ".*",
echo   "write": ".*",
echo   "read": ".*"
echo  },
echo  {
echo   "user": "%RO_USER%",
echo   "vhost": "\/",
echo   "configure": "",
echo   "write": "",
echo   "read": ".*"
echo  }
echo  ],
echo  "parameters": [],
echo  "policies": [],
echo  "queues": [],
echo  "exchanges": [],
echo  "bindings": []
echo }
) > C:\data\config\user-definitions.json

(
echo  [
echo    {rabbit, 		[
echo			{tcp_listeners, [5672]},
echo			{loopback_users, []},
echo			{total_memory_available_override_value, "%MEMORY_AVAILABLE%"},
echo			{disk_free_limit, "%DISK_FREE_LIMIT%"}
echo		]},
echo		{rabbitmq_management, [
echo		  {load_definitions, "C:/data/config/user-definitions.json"}
echo		]}
echo  ].
) > C:\data\config\rabbitmq.config


rabbitmq-server