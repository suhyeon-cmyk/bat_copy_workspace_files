@echo off
rem UTF-8 한글 깨짐 방지 및 변수 지역화
chcp 65001 > nul
setlocal enabledelayedexpansion

rem =========================================================
rem 0. 안전한 날짜 추출 (PowerShell 활용)
rem =========================================================
for /f "tokens=*" %%I in ('powershell -Command "Get-Date -Format 'yyyyMMdd'"') do set "TODAY=%%I"

rem =========================================================
rem 기존 폴더/로그가 있으면 순번(_001, _002...)을 자동으로 증가
rem =========================================================
set /a num=1

:LOOP_NUM
set "NUM_STR=000!num!"
set "NUM_STR=!NUM_STR:~-3!"

set "TARGET_DIR_NAME=copy_files_%TODAY%_!NUM_STR!"
set "TARGET_PATH=%~dp0!TARGET_DIR_NAME!"
set "LOG_FILE=%~dp0copy_log_%TODAY%_!NUM_STR!.txt"

if exist "%TARGET_PATH%" (
    set /a num+=1
    goto LOOP_NUM
)
if exist "%LOG_FILE%" (
    set /a num+=1
    goto LOOP_NUM
)

:INPUT_BASE
echo --------------------------------------------------------
echo 1. 최상위 폴더 경로를 입력하세요.
echo (예: D:\wings\eclipse-workspace3_eol)
echo --------------------------------------------------------
set /p "BASE_DIR=경로 입력: "

set "BASE_DIR=%BASE_DIR:"=%"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

if not exist "%BASE_DIR%" (
    echo [오류] 입력하신 경로가 존재하지 않습니다. 다시 입력해주세요.
    goto INPUT_BASE
)

:INPUT_SOURCE_TYPE
echo.
echo --------------------------------------------------------
echo 2. 가져올 파일의 출처를 선택하세요 (1 또는 2 입력)
echo --------------------------------------------------------
echo [1] 개발 소스 파일 (src 폴더부터 가져옴)
echo [2] 서버에서 가져온 파일 (WEB-INF 폴더부터 가져옴)
echo --------------------------------------------------------
set /p "SOURCE_TYPE=선택 (1/2): "

if not "%SOURCE_TYPE%"=="1" if not "%SOURCE_TYPE%"=="2" (
    echo [오류] 1 또는 2만 입력 가능합니다.
    goto INPUT_SOURCE_TYPE
)

:INPUT_MODE
echo.
echo --------------------------------------------------------
echo 3. 복사 방식을 선택하세요 (1 또는 2 입력)
echo --------------------------------------------------------
echo [1] 하나의 폴더에 모두 모아서 넣기
echo [2] 선택한 기준 폴더부터 하위 구조 유지하며 넣기
echo --------------------------------------------------------
set /p "COPY_MODE=선택 (1/2): "

if not "%COPY_MODE%"=="1" if not "%COPY_MODE%"=="2" (
    echo [오류] 1 또는 2만 입력 가능합니다.
    goto INPUT_MODE
)

if "%SOURCE_TYPE%"=="1" (
    set "TYPE_TEXT=개발 소스 파일"
    set "CUT_KEYWORD=src"
) else (
    set "TYPE_TEXT=서버 배포 파일"
    set "CUT_KEYWORD=WEB-INF"
)

if "%COPY_MODE%"=="1" (
    set "MODE_TEXT=1번 방식 -> 하나의 폴더에 모두 모아서 넣기"
) else (
    set "MODE_TEXT=2번 방식 -> 구조 유지하며 넣기 (%TYPE_TEXT% 기준)"
)

echo.
echo --------------------------------------------------------
echo 4. 파일 경로 목록을 붙여넣으세요.
echo 입력이 끝나면 [엔터(Enter)]를 한 번 더 누르세요.
echo --------------------------------------------------------

rem 임시 파일 생성하여 입력받은 목록 저장
set "TEMP_LIST=%TEMP%\file_list_input.txt"
if exist "%TEMP_LIST%" del "%TEMP_LIST%"

:INPUT_LOOP
set "LINE="
set /p "LINE="
if "%LINE%"=="" goto START_COPY
set "LINE=%LINE:"=%"
echo !LINE!>> "%TEMP_LIST%"
goto INPUT_LOOP


:START_COPY
if not exist "%TEMP_LIST%" (
    echo [오류] 입력된 파일 경로가 없습니다. 프로그램을 종료합니다.
    pause
    exit /b
)

mkdir "%TARGET_PATH%"

rem 로그 파일 헤더 작성
echo ======================================================== >> "%LOG_FILE%"
echo  파일 복사 작업 로그 (%DATE% %TIME%) >> "%LOG_FILE%"
echo  최상위 경로: %BASE_DIR% >> "%LOG_FILE%"
echo  파일 출처  : %TYPE_TEXT% >> "%LOG_FILE%"
echo  복사 방식  : %MODE_TEXT% >> "%LOG_FILE%"
echo ======================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

echo.
echo --------------------------------------------------------
echo [파일 복사 시작] 대상 폴더: \!TARGET_DIR_NAME!\
echo --------------------------------------------------------

set /a count=0
set /a success=0

for /f "usebackq delims=" %%F in ("%TEMP_LIST%") do (
    set /a count+=1
    
    set "RAW_PATH=%%F"
    set "RAW_PATH=!RAW_PATH:/=\!"
    
    set "TEST_BASE=%BASE_DIR%\"
    if /i not "!RAW_PATH:~0,4!"=="http" (
        set "RAW_PATH=!RAW_PATH:%BASE_DIR%=!"
    )
    if "!RAW_PATH:~0,1!"=="\" set "RAW_PATH=!RAW_PATH:~1!"
    
    set "FULL_SOURCE_PATH=%BASE_DIR%\!RAW_PATH!"
    
    rem 입력된 파일의 확장자 확인 (.java 인지 판별)
    for %%A in ("!FULL_SOURCE_PATH!") do set "FILE_EXT=%%~xA"
    
    if /i "!FILE_EXT!"==".java" (
        rem --------------------------------------------------------
        rem [특수 처리] .java 파일인 경우 관련된 .class 파일들을 추적
        rem --------------------------------------------------------
        for %%A in ("!FULL_SOURCE_PATH!") do (
            set "FILE_DIR=%%~dpA"
            set "FILE_NAME=%%~nA"
        )
        
        rem 원본 .java 파일 위치에 컴파일된 .class가 같이 있는지 체크 (또는 경로 매핑 대응)
        rem 대다수 서버 배포본 빌드 환경이나 이클립스/웹서버 구조 연동을 위해 해당 디렉토리 검색
        set "FOUND_JAVA_CLASS=0"
        
        for /f "tokens=*" %%C in ('dir /b "!FILE_DIR!!FILE_NAME!*.class" 2^>nul') do (
            set "FOUND_JAVA_CLASS=1"
            set "CLASS_FULL_FILE=!FILE_DIR!%%C"
            set "CLASS_REL_PATH=!RAW_PATH:%%~nxA=%%C!"
            
            if "%COPY_MODE%"=="1" (
                copy /Y "!CLASS_FULL_FILE!" "%TARGET_PATH%" > nul
                set "MSG=[성공(Java연관)] !RAW_PATH! -> %%C (모아서 저장)"
            ) else (
                set "NEW_PATH="
                for /f "tokens=*" %%P in ('powershell -Command "$p='!CLASS_REL_PATH!'; $k='%CUT_KEYWORD%'; $idx=$p.IndexOf('\'+$k+'\'); if($idx -ge 0){$p.Substring($idx+1)}else if($p.StartsWith($k+'\')){$p}else{$p}"') do set "NEW_PATH=%%P"
                if "!NEW_PATH!"=="" set "NEW_PATH=!CLASS_REL_PATH!"
                
                for %%D in ("%TARGET_PATH%\!NEW_PATH!") do set "DEST_DIR=%%~dpD"
                if not exist "!DEST_DIR!" mkdir "!DEST_DIR!"
                copy /Y "!CLASS_FULL_FILE!" "!DEST_DIR!" > nul
                set "MSG=[성공(Java연관)] !NEW_PATH!"
            )
            echo !MSG!
            echo !MSG! >> "%LOG_FILE%"
            set /a success+=1
        )
        
        if "!FOUND_JAVA_CLASS!"=="0" (
            set "MSG=[실패] .java와 연관된 .class 파일을 찾을 수 없음: !FILE_DIR!!FILE_NAME!*.class"
            echo !MSG!
            echo !MSG! >> "%LOG_FILE%"
        )
        
    ) else (
        rem --------------------------------------------------------
        rem [일반 처리] .java가 아닌 다른 모든 파일 (.jsp, .xml, .class 등)
        rem --------------------------------------------------------
        if exist "!FULL_SOURCE_PATH!" (
            if "%COPY_MODE%"=="1" (
                copy /Y "!FULL_SOURCE_PATH!" "%TARGET_PATH%" > nul
                set "MSG=[성공] !RAW_PATH! -> 모아서 저장"
            ) else (
                set "NEW_PATH="
                for /f "tokens=*" %%P in ('powershell -Command "$p='!RAW_PATH!'; $k='%CUT_KEYWORD%'; $idx=$p.IndexOf('\'+$k+'\'); if($idx -ge 0){$p.Substring($idx+1)}else if($p.StartsWith($k+'\')){$p}else{$p}"') do set "NEW_PATH=%%P"
                if "!NEW_PATH!"=="" set "NEW_PATH=!RAW_PATH!"

                for %%A in ("%TARGET_PATH%\!NEW_PATH!") do set "DEST_DIR=%%~dpA"
                if not exist "!DEST_DIR!" mkdir "!DEST_DIR!"
                copy /Y "!FULL_SOURCE_PATH!" "!DEST_DIR!" > nul
                set "MSG=[성공] !NEW_PATH!"
            )
            set /a success+=1
        ) else (
            set "MSG=[실패] 파일을 찾을 수 없음: !FULL_SOURCE_PATH!"
        )
        echo !MSG!
        echo !MSG! >> "%LOG_FILE%"
    )
)

rem 임시 파일 삭제
del "%TEMP_LIST%"

rem 로그 파일 푸터 작성
echo. >> "%LOG_FILE%"
echo -------------------------------------------------------- >> "%LOG_FILE%"
echo [복사 완료] 총 %count%개 라인 처리 중 %success%개 파일 복사 완료. >> "%LOG_FILE%"
echo -------------------------------------------------------- >> "%LOG_FILE%"

echo --------------------------------------------------------
echo [복사 완료] 총 %count%개 라인 처리 중 %success%개 파일 복사 완료.
echo 저장 위치: .\!TARGET_DIR_NAME!\
echo 로그 파일: .\copy_log_%TODAY%_!NUM_STR!.txt
echo --------------------------------------------------------
pause