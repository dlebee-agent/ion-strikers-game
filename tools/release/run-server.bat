@echo off
rem Launch the Ion Strikers dedicated server from a release archive.
rem
rem Every argument is forwarded, so anything boot.gd parses works:
rem
rem   run-server.bat --port 7777 --mgmt-port 9090 ^
rem       --register --allow-dynamic-create --api-url https://api.example.com ^
rem       --public-host game.example.com --server-id eu-west-1 ^
rem       --join-secret %%JOIN_TOKEN_SECRET%%
rem
rem The .console.exe variant is preferred so log output reaches this terminal.
setlocal
set "HERE=%~dp0"
set "BIN=%HERE%ion-strikers-server.console.exe"
if not exist "%BIN%" set "BIN=%HERE%ion-strikers-server.exe"
if not exist "%BIN%" (
	echo run-server: no server binary found next to %HERE% 1>&2
	exit /b 1
)
"%BIN%" --headless -- --dedicated %*
