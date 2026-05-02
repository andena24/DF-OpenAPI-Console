#########################################################
#region 명세서
#########################################################
<#

.버전
    1.0.0

.개요
    DF OpenAPI Console 프로젝트의 핵심모듈 입니다.

.설명
    던파 OpenAPI 서버에 데이터를 요청하고 응답 결과를 받아오는 핵심기능 함수와, 편의를 위한 공용 함수가 포함되어 있습니다.
    
.연락채널
    - GitHub : https://github.com/andena24
    - YouTube : https://www.youtube.com/@%EC%95%8A%EB%8D%B0%EB%83%90
    - Discord : @andena24
    - KakaoTalk : https://open.kakao.com/o/sj9iTcpi

.라이센스
    Copyright (c) 2026 않데냐
    Licensed under the GNU General Public License, Version 3.0

#>
#endregion
#########################################################
#region 사용자 설정

# '콘솔 화면 갱신' 단축키 관련
$KeyStr = "F6"; 
$MenuTitle = "콘솔 화면 갱신";

# 던파 OpenAPI 관련 설정 (* 공통 가이드 https://developers.neople.co.kr/contents/guide/pages/all 참조)
$REQ_GAP = 2; # 1초에 500회 API요청 가능에 따른 설정값 (ms단위)

#endregion
#########################################################
#region 시스템 설정

# 콘솔 화면 갱신에 대한, 단축키(F6) 등록 (상단의 "추가 기능(A)"에서 적용 여부 확인가능)
if($psISE) {
    $ExistingMenu = $psISE.CurrentPowerShellTab.AddOnsMenu.Submenus | Where-Object { $_.DisplayName -eq $MenuTitle }
    if (-not $ExistingMenu) {
        $psISE.CurrentPowerShellTab.AddOnsMenu.Submenus.Add($MenuTitle, { Clear-Host }, $KeyStr);
    }
}

# 비종료 에러를 종료 에러로 취급 (try-catch 관련)
$ErrorActionPreference = "Stop";

# API서버와의 연결세션 재사용
if($ConnSession -eq $null) { $ConnSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession }

# 던파 OpenAPI 관련 셋팅값
$BASE_URL = "https://api.neople.co.kr";

#endregion
#########################################################
#region 시스템 함수

# 에러 메시지 처리
function onError($Value) {
    $Msg = $Value.Exception.Message;
    $ErrorTrace = $Value.ScriptStackTrace;

    $Text = "`n`t[ 오류 ]`n"`
          + "`n내용 : {0}" -f $Msg`
          + "`n$ErrorTrace";
    Write-Host $Text -ForegroundColor Yellow;
}

# 성능측정
function checkPerformance([string]$Name, $Mode, [scriptblock]$Code) {
    if(($null -eq $Mode) -or ($Mode -isnot [int])) {
        $Text = "`n`t[ 오류 ]`n"`
              + "`n내용 : checkPerformance 함수에서 2번째 매개변수가 누락되었습니다."`
              + " 성능체크를 활성화하려면 1, 비활성화하려면 0을 입력하세요.";
        Write-Host $Text -ForegroundColor Yellow;
        return;
    }
    
    $Timer = $null;
    if($Mode -eq 1) {
        $Timer = [System.Diagnostics.Stopwatch]::StartNew();
    }

    try {
        Write-Host "`n`t[ 실행결과 ]`n";
        & $Code;

    } catch {
        onError($_);

    } finally {
        if($null -ne $Timer) {
            $Timer.Stop();

            $Text = "`n`t[ 성능측정 ]`n"`
                  + "`n측정대상 : {0}" -f $Name`
                  + "`n소요시간 : {0} ms" -f $Timer.Elapsed.TotalMilliseconds;
            Write-Host $Text -ForegroundColor Cyan;
        }
    }
}

#endregion
#########################################################
#region 공용 함수

# 문자열 URL인코딩
function 인코딩($Value) {
    return [Uri]::EscapeDataString($Value);
}

# 문자열 왼쪽 정렬
function 좌측정렬($Width, $Value) {
    $Length = [System.Text.Encoding]::Default.GetByteCount($Value);

    $PadCount = $Width - $Length;
    if($PadCount -lt 0) {
        throw "PaddingWidth가 입력값의 크기보다 작습니다.(너비 : {0}, 입력값의 크기 : {1})" -f $Width, $Length;
    }

    return $Value + (" " * $PadCount);
}

# 문자열 오른쪽 정렬
function 우측정렬($Width, $Value) {
    $Length = [System.Text.Encoding]::Default.GetByteCount($Value);

    $PadCount = $Width - $Length;
    if($PadCount -lt 0) {
        throw "PaddingWidth가 입력값의 크기보다 작습니다.(너비 : {0}, 입력값의 크기 : {1})" -f $Width, $Length;
    }

    return (" " * $PadCount) + $Value;
}

# 소수점 버림
function 소수버림($Value) {
    return [Math]::Floor($Value);
}

# 한국식 숫자 단위로 변환 (문자열로 반환됨)
function 한글단위($Value) {
    # 파라미터 검사
    if($Value -ge 1e12) {
        throw "1조 미만의 값만 입력할 수 있습니다. 입력값 : {0:N0}" -f $Value;
    }

    # 계산
    $Eok = [math]::Floor($Value / 1e8);
    $Man = [math]::Floor($($Value % 1e8) / 1e4);
    $Rem = $Value % 1e4;

    # 문자열 처리
    $EokStr = if($Eok -gt 0) {"${Eok}억"} else {""}
    $ManStr = if($Man -gt 0) {"${Man}만"} else {""}
    $RemStr = if($Rem -gt 0) {"${Rem}"} elseif($Value -eq 0) {"0"} else {""}

    # 결과 반환
    return "{0} {1} {2}" -f (우측정렬 6 $EokStr), (우측정렬 6 $ManStr), (우측정렬 4 $RemStr);
}

# 현재 시간과 비교 (날짜의 경우, 24시간 기준으로까지만 계산됩니다.)
function 남은시간($Value) {
    $Target = [datetime]::Parse($Value);
    $Now = Get-Date;

    if($Target -lt $Now) {
        return "기간만료";

    } else {
        $Diff = $Target - $Now;
        return "{0,2}시간 {1,2}분 {2,2}초" -f $Diff.Hours, $Diff.Minutes, $Diff.Seconds;
    }
}

#endregion
#########################################################
#region 핵심기능

function 서버요청([hashtable]$BaseParams, [hashtable]$AddParams) {
    # 파라미터 검사
    if($null -eq $BaseParams) {
        throw "'서버요청'함수의 1번째 매개변수가 누락되었습니다.";
    } elseif($BaseParams.API_TYPE -eq $null) {
        throw "'서버요청'함수의 1번째 매개변수에서 'API_TYPE'가 누락되었습니다.";
    } elseif($BaseParams.API_PARAMS -eq $null) {
        throw "'서버요청'함수의 1번째 매개변수에서 'API_PARAMS'가 누락되었습니다.";
    } elseif($null -eq $AddParams) {
        throw "'서버요청'함수의 2번째 매개변수가 누락되었습니다.";
    } elseif($AddParams.Count -eq 0) {
        throw "'서버요청'함수의 2번째 매개변수에 올바른 내용을 입력하세요";
    }

    # 헤더 정의
    $Header = @{
        apikey = $API_KEY;
    }

    # 파라미터 통합
    $TotalParams = @{};
    $TotalParams = $BaseParams.API_PARAMS + $AddParams;

    # URL 조립
    $Url = $BASE_URL + $BaseParams.API_TYPE + "?";
    $Url += [string]::Join("&", ($TotalParams.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }));

    # 데이터 요청
    $Response = Invoke-RestMethod -Uri $Url -Method Get -Headers $Header -WebSession $ConnSession;
    Start-Sleep -Milliseconds $REQ_GAP;

    # 결과 반환
    return $Response;
}

#endregion