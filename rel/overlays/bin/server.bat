call "%~dp0\leaf" eval Leaf.Release.check_migrated || exit /b 1
set PHX_SERVER=true
call "%~dp0\leaf" start
