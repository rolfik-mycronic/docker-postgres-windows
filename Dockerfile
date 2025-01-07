####
#### argument for Windows version must be set early
####
ARG WIN_VER

####
#### Download and prepare PostgreSQL for Windows
####
FROM mcr.microsoft.com/windows/servercore:${WIN_VER} as prepare

### Set the variables for EnterpriseDB
ARG EDB_VER
ENV EDB_VER $EDB_VER
ENV EDB_REPO https://get.enterprisedb.com/postgresql

##### Use PowerShell for the installation
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop';$ProgressPreference = 'SilentlyContinue';"]

ENV EDB_URL=$EDB_REPO/postgresql-$EDB_VER-windows-x64-binaries.zip
ENV EDB_ZIP=C:\\EnterpriseDB.zip

### Download EnterpriseDB and remove cruft
RUN echo Downloading $env:EDB_URL;\
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;\
    Invoke-WebRequest -Uri "$env:EDB_URL" -OutFile "$env:EDB_ZIP"
RUN echo Installing $env:EDB_ZIP;\
    Expand-Archive "$env:EDB_ZIP" -DestinationPath 'C:\\' ; \
    Remove-Item -Path "$env:EDB_ZIP" ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\doc' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\include' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\pgAdmin*' ; \
    Remove-Item -Recurse -Force –Path 'C:\\pgsql\\StackBuilder'

### Make the sample config easier to munge (and "correct by default")
RUN $SAMPLE_FILE = 'C:\\pgsql\\share\\postgresql.conf.sample' ; \
    $SAMPLE_CONF = Get-Content $SAMPLE_FILE ; \
    $SAMPLE_CONF = $SAMPLE_CONF -Replace '#listen_addresses = ''localhost''','listen_addresses = ''*''' ; \
    $SAMPLE_CONF | Set-Content $SAMPLE_FILE

ENV VCLIBS_NEW='Using Visual C++ 140 OneCore dlls from Visual Studio 2022 located at eg. C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Redist\MSVC\14.42.34433\onecore\x64\Microsoft.VC143.CRT'
ENV VCLIBS_OLD='Visual C++ 2013 Redistributable Package'

### Install correct Visual C++ Redistributable Package
# MI: See VC140 OneCore dlls discussion at https://github.com/dotnet/runtime/issues/40131#issuecomment-670077781 I was inspired to look at which allowed to make postgres.exe 15 work
ADD Microsoft.VC143.CRT c:\\MSVC
RUN if (($env:EDB_VER -like '9.*') -or ($env:EDB_VER -like '10.*')) { \
        Write-Host($env:VCLIBS_OLD) ; \
        $URL2 = 'https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe' ; \
    } else { \
        Write-Host($env:VCLIBS_NEW) ; \
        exit;\
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
        Write-Host($env:VCLIBS_OLD) ; \
        Copy-Item 'C:\\windows\\system32\\msvcp120.dll' -Destination 'C:\\pgsql\\bin\\msvcp120.dll' ; \
        Copy-Item 'C:\\windows\\system32\\msvcr120.dll' -Destination 'C:\\pgsql\\bin\\msvcr120.dll' ; \
    } else { \
        Write-Host($env:VCLIBS_NEW) ; \
        Copy-Item 'C:\\MSVC\\*' -Destination 'C:\\pgsql\\bin' ; \
    }

####
#### PostgreSQL on Windows Nano Server
####
FROM mcr.microsoft.com/windows/nanoserver:${WIN_VER}

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
