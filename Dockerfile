####
#### Download and prepare PostgreSQL for Windows
####
ARG TAG_VER
FROM mcr.microsoft.com/windows/servercore:${TAG_VER} as prepare

### Set the variables for EnterpriseDB
ARG EDB_VER
ENV EDB_VER $EDB_VER
ENV EDB_REPO https://get.enterprisedb.com/postgresql

##### Use PowerShell for the installation
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

### Download EnterpriseDB and remove cruft
RUN $URL1 = $('{0}/postgresql-{1}-windows-x64-binaries.zip' -f $env:EDB_REPO,$env:EDB_VER) ; \
    Invoke-WebRequest -Uri $URL1 -OutFile 'C:\\EnterpriseDB.zip' ; \
    Expand-Archive 'C:\\EnterpriseDB.zip' -DestinationPath 'C:\\' ; \
    Remove-Item -Path 'C:\\EnterpriseDB.zip' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\doc' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\include' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\pgAdmin*' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\StackBuilder'

### Make the sample config easier to munge (and "correct by default")
RUN $SAMPLE_FILE = 'C:\\pgsql\\share\\postgresql.conf.sample' ; \
    $SAMPLE_CONF = Get-Content $SAMPLE_FILE ; \
    $SAMPLE_CONF = $SAMPLE_CONF -Replace '#listen_addresses = ''localhost''','listen_addresses = ''*''' ; \
    $SAMPLE_CONF | Set-Content $SAMPLE_FILE

### Install correct Visual C++ Redistributable Package
RUN if (($env:EDB_VER -eq '9.4.24-2') -or ($env:EDB_VER -eq '9.5.19-2') -or ($env:EDB_VER -eq '9.6.15-2') -or ($env:EDB_VER -eq '10.10-2')) { \
        Write-Host('Visual C++ 2013 Redistributable Package') ; \
        $URL2 = 'https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe' ; \
    } else { \
        Write-Host('Visual C++ 2017 Redistributable Package') ; \
        $URL2 = 'https://download.visualstudio.microsoft.com/download/pr/11100230/15ccb3f02745c7b206ad10373cbca89b/VC_redist.x64.exe' ; \
    } ; \
    Invoke-WebRequest -Uri $URL2 -OutFile 'C:\\vcredist.exe' ; \
    Start-Process 'C:\\vcredist.exe' -Wait \
        -ArgumentList @( \
            '/install', \
            '/passive', \
            '/norestart' \
        )

# Determine new files installed by VC Redist
# RUN Get-ChildItem -Path 'C:\\Windows\\System32' | Sort-Object -Property LastWriteTime | Select Name,LastWriteTime -First 25

# Copy relevant DLLs to PostgreSQL
RUN if (Test-Path 'C:\\windows\\system32\\msvcp120.dll') { \
        Write-Host('Visual C++ 2013 Redistributable Package') ; \
        Copy-Item 'C:\\windows\\system32\\msvcp120.dll' -Destination 'C:\\pgsql\\bin\\msvcp120.dll' ; \
        Copy-Item 'C:\\windows\\system32\\msvcr120.dll' -Destination 'C:\\pgsql\\bin\\msvcr120.dll' ; \
    } else { \
        Write-Host('Visual C++ 2017 Redistributable Package') ; \
        Copy-Item 'C:\\windows\\system32\\vcruntime140.dll' -Destination 'C:\\pgsql\\bin\\vcruntime140.dll' ; \
    }

####
#### PostgreSQL on Windows Nano Server
####
ARG TAG_VER
FROM mcr.microsoft.com/windows/nanoserver:${TAG_VER}

RUN mkdir "C:\\docker-entrypoint-initdb.d"

#### Copy over PostgreSQL
COPY --from=prepare /pgsql /pgsql

#### In order to set system PATH, ContainerAdministrator must be used
USER ContainerAdministrator
RUN setx /M PATH "C:\\pgsql\\bin;%PATH%"
USER ContainerUser
ENV PGDATA "C:\\pgsql\\data"

COPY docker-entrypoint.cmd /
ENTRYPOINT ["C:\\docker-entrypoint.cmd"]

EXPOSE 5432
CMD ["postgres"]
