@echo off
rem UTF-8 한글 깨짐 방지 및 변수 지역화
chcp 65001 > nul
setlocal enabledelayedexpansion

rem =========================================================
rem 0. 안전한 날짜 추출 (PowerShell 활용)
rem =========================================================
for /f "tokens=*" %%I in ('powershell -Command "Get-Date -Format 'yyyyMMdd'"') do set "TODAY=%%I"

rem =========================================================
rem [수정] 기존 폴더가 있으면 순번(_001, _002...)을 자동으로 증가
rem =========================================================
set /a num=1

:LOOP_NUM
rem 3자리 포맷팅 (예: 1 -> 001, 12 -> 012)
set "NUM_STR=000!num!"
set "NUM_STR=!NUM_STR:~-3!"

set "TARGET_DIR_NAME=copy_files_%TODAY%_!NUM_STR!"
set "TARGET_PATH=%~dp0!TARGET_DIR_NAME!"
set "LOG_FILE=%~dp0copy_log_%TODAY%_!NUM_STR!.txt"

rem 폴더나 로그 파일 중 하나라도 이미 존재하면 번호 증가 후 다시 체크
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

rem 입력값 양 끝의 따옴표 제거 및 마지막 \ 제거 처리
set "BASE_DIR=%BASE_DIR:"=%"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

if not exist "%BASE_DIR%" (
    echo [오류] 입력하신 경로가 존재하지 않습니다. 다시 입력해주세요.
    goto INPUT_BASE
)

:INPUT_MODE
echo.
echo --------------------------------------------------------
echo 2. 복사 방식을 선택하세요 (1 또는 2 입력)
echo --------------------------------------------------------
echo [1] 하나의 폴더에 모두 모아서 넣기
echo     (예: !TARGET_DIR_NAME!\in02_0100_V03.jsp)
echo [2] src 폴더부터 하위 구조 유지하며 넣기
echo     (예: !TARGET_DIR_NAME!\src\main\webapp\...\in02_0100_V03.jsp)
echo --------------------------------------------------------
set /p "COPY_MODE=선택 (1/2): "

if not "%COPY_MODE%"=="1" if not "%COPY_MODE%"=="2" (
    echo [오류] 1 또는 2만 입력 가능합니다.
    goto INPUT_MODE
)

rem 로그용 텍스트 변수 설정
if "%COPY_MODE%"=="1" (
    set "MODE_TEXT=1번 방식 -> 하나의 폴더에 모두 모아서 넣기"
) else (
    set "MODE_TEXT=2번 방식 -> src 폴더부터 하위 구조 유지하며 넣기"
)

echo.
echo --------------------------------------------------------
echo 3. 파일 경로 목록을 붙여넣으세요.
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

rem 최종 결정된 대상 폴더 생성
mkdir "%TARGET_PATH%"

rem 로그 파일 헤더 작성
echo ======================================================== >> "%LOG_FILE%"
echo  파일 복사 작업 로그 (%DATE% %TIME%) >> "%LOG_FILE%"
echo  최상위 경로: %BASE_DIR% >> "%LOG_FILE%"
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
    if "!RAW_PATH:~0,1!"=="/" set "RAW_PATH=!RAW_PATH:~1!"
    if "!RAW_PATH:~0,1!"=="\" set "RAW_PATH=!RAW_PATH:~1!"
    
    rem 슬래시(/)를 역슬래시(\)로 변환
    set "REL_PATH=!RAW_PATH:/=\!"
    
    rem 원본 파일의 전체 절대 경로 생성
    set "FULL_SOURCE_PATH=%BASE_DIR%\!REL_PATH!"

    rem 파일 존재 여부 확인 후 복사 진행
    if exist "!FULL_SOURCE_PATH!" (
        if "%COPY_MODE%"=="1" (
            rem [방식 1] 하나의 폴더에 파일 이름만 추출해서 복사
            copy /Y "!FULL_SOURCE_PATH!" "%TARGET_PATH%" > nul
            set "MSG=[성공] !REL_PATH! -> 모아서 저장"
        ) else (
            rem [방식 2] src 폴더 기점으로 경로 잘라내기
            set "SRC_PATH=!REL_PATH!"
            if not "!SRC_PATH:\src\=!"=="!SRC_PATH!" (
                set "SRC_PATH=src\!SRC_PATH:*_eol\src\=!"
                set "SRC_PATH=src\!SRC_PATH:*\src\=!"
            )
            
            for %%A in ("%TARGET_PATH%\!SRC_PATH!") do set "DEST_DIR=%%~dpA"
            if not exist "!DEST_DIR!" mkdir "!DEST_DIR!"
            copy /Y "!FULL_SOURCE_PATH!" "!DEST_DIR!" > nul
            set "MSG=[성공] !SRC_PATH!"
        )
        set /a success+=1
    ) else (
        set "MSG=[실패] 파일을 찾을 수 없음: !FULL_SOURCE_PATH!"
    )
    
    rem 화면 출력 및 로그 파일 동시 기록
    echo !MSG!
    echo !MSG! >> "%LOG_FILE%"
)

rem 임시 파일 삭제
del "%TEMP_LIST%"

rem 로그 파일 푸터 작성
echo. >> "%LOG_FILE%"
echo -------------------------------------------------------- >> "%LOG_FILE%"
echo [복사 완료] 총 %count%개 중 %success%개 파일 복사 성공. >> "%LOG_FILE%"
echo -------------------------------------------------------- >> "%LOG_FILE%"

echo --------------------------------------------------------
echo [복사 완료] 총 %count%개 중 %success%개 파일 복사 성공.
echo 저장 위치: .\!TARGET_DIR_NAME!\
echo 로그 파일: .\copy_log_%TODAY%_!NUM_STR!.txt
echo --------------------------------------------------------
pause