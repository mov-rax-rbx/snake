@echo off

@REM path to NASM + some flags
SET NASM=..\nasm -O3
@REM path to golink
SET GOLINK=..\golink

%NASM% -f win64 console_win32_snake.asm -o console_win32_snake.obj
%GOLINK% /entry:start /console kernel32.dll user32.dll console_win32_snake.obj

pause
exit