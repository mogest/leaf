if "%~1"=="" (
  echo usage: %~nx0 ^<version^>
  exit /b 1
)
call "%~dp0\leaf" eval "Leaf.Release.rollback(%~1)"
