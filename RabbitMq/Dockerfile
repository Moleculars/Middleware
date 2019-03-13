# sources are available : https://github.com/Moleculars/Middleware

# Stupidly, the only install method offered by Erlang is NSIS setup.exe, requiring GUI libs and admin permissions.
# So we use a windows core-based image and run it as administrator.
FROM microsoft/powershell:windowsservercore-1709 as installer

SHELL ["pwsh.exe", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV RABBIT_VERSION=3.7.7 \
    ERLANG_VERSION=20.3
ENV RABBIT_URL=https://dl.bintray.com/rabbitmq/windows/rabbitmq-server-windows-${RABBIT_VERSION}.zip \
    ERLANG_URL=http://erlang.org/download/otp_win64_${ERLANG_VERSION}.exe

RUN mkdir /TEMP 2>&1 >$null; \
    Write-Host ('Downloading {0} ...' -f $env:RABBIT_URL); \
    Invoke-WebRequest -Uri $env:RABBIT_URL -OutFile /TEMP/rabbitmq.zip -Proxy $ENV:HTTP_PROXY; \
    Write-Host ('Downloading {0} ...' -f $env:ERLANG_URL); \
    Invoke-WebRequest -Uri $env:ERLANG_URL -OutFile /TEMP/erlang.exe -Proxy $ENV:HTTP_PROXY

RUN Write-Host 'Installing Erlang...'; \
    Start-Process /TEMP/erlang.exe -NoNewWindow -Wait -ArgumentList '/S','/D=C:\otp\erlang'; \
    rm -Force C:\otp\erlang\Install.exe,C:\otp\erlang\Uninstall.exe,C:\otp\erlang\vcredist_x64.exe; \
    Write-Host 'Installing Rabbit...'; \
    Expand-Archive -Path /TEMP/rabbitmq.zip -DestinationPath C:/otp/rabbitmq/; \
    mv C:/otp/rabbitmq/rabbitmq_server*/* C:/otp/rabbitmq/

# Copy this in this build image to avoid creating a layer in the final image.
COPY handle.exe C:/otp/rabbitmq/sbin/



FROM microsoft/nanoserver:1709

USER ContainerAdministrator
COPY --from=installer C:/otp C:/otp

ENV ADMIN_USER=admin \
    ADMIN_PASS=kkjsdqjhfgjh9879878788 \
    RW_USER=rw \
    RW_PASS=jlkjhsdfljklkjsdflkjl \
    RO_USER=ro\
    RO_PASS=FFYTETRDFYGFYDTRDFG444 \
    MEMORY_AVAILABLE=1GB \
    DISK_FREE_LIMIT=1GB

RUN setx PATH %PATH%;C:\otp\rabbitmq\sbin && \
    setx ERLANG_HOME C:\otp\erlang\ && \
    setx RABBITMQ_SERVER_ERL_ARGS " -setcookie MARSU " && \
    setx RABBITMQ_CTL_ERL_ARGS " -setcookie MARSU " && \
    setx RABBITMQ_BASE C:\data\ && \
    setx RABBITMQ_CONFIG_FILE C:\data\config\rabbitmq && \
    setx RABBITMQ_NODENAME rabbit@localhost && \
    setx HOMEDRIVE C:\ && \
    setx HOMEPATH data && \
    mkdir C:\data\config

RUN rabbitmq-plugins enable rabbitmq_management --offline && \
    del /F /Q C:\data\log\* && \
    rmdir /S /Q C:\data\db\ && \
    mkdir C:\data\db

EXPOSE 5672 15672

VOLUME C:/data/db

# copy run script, that creates json files with the rabbit users, based on the latter env variables
COPY run.bat C:/data/bin/

HEALTHCHECK --interval=60s --retries=3 --start-period=130s --timeout=30s CMD [ "C:/otp/rabbitmq/sbin/rabbitmqctl.bat",  "node_health_check" ]

ENTRYPOINT C:/data/bin/run.bat
