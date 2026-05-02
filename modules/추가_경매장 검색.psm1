#########################################################
#region 명세서
#########################################################
<#

.버전
    1.0.0

.개요
    DF OpenAPI Console 프로젝트의 경매장 검색 모듈입니다.

.설명
    아이템 검색, 경매장 검색, 경매장 시세검색을 구현한 함수가 포함되어있습니다.
    
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
#region 시스템 설정

$PaddingWidth = 12; # 직업명 중에서 가장 긴 '프리스트(남)' 기준 (한글은 2칸)

#region 조사 (메인 : full, 보조 : front)
$Config1 = @{
    API_TYPE = "/df/items"
    API_PARAMS = @{
        limit    = 100
        wordType = "full"
    }
}

$Config2 = @{
    API_TYPE = "/df/items"
    API_PARAMS = @{
        limit    = 100
        wordType = "front"
    }
}
#endregion

#region 횡검색
$Config3 = @{
    API_TYPE = "/df/auction"
    API_PARAMS = @{
        limit     = 20
        wordType  = "front"
        wordShort = "true"
        sort      = "unitPrice:asc"
    }
}
#endregion

#region 종검색
$Config4 = @{
    API_TYPE = "/df/auction"
    API_PARAMS = @{
        limit     = 100
        wordType  = "front"
        wordShort = "true"
        sort      = "unitPrice:asc"
    }
}

$Config5 = @{
    API_TYPE = "/df/auction-sold"
    API_PARAMS = @{
        limit     = 100
        wordType  = "front"
        wordShort = "true"
    }
}
#endregion

#endregion
#########################################################
#region 함수

# 특정 아이템의 id를 확인하는데 사용
function 조사($Value) {
    # 1차 검색
    $AddParams = @{ itemName = 인코딩('"{0}"' -f $Value); }
    $Response = 서버요청 $Config1 $AddParams;

    # 2차 검색
    if($Response.rows.Count -eq 0) {
        $AddParams = @{ itemName = 인코딩($Value); }
        $Response = 서버요청 $Config2 $AddParams;
    }

    # 최종 결과 출력
    if($Response.rows.Count -eq 0) {
        Write-Host "- 검색결과 없음`n`n검색어에 '1 글자 단어'가 포함되어있는 경우, 왼쪽에서부터 정확히 입력해보세요`n";

    } else {
        $Response.rows | ForEach-Object {
            $JobInfo = if($_.jobs) { $_.jobs[0].jobName } else { "(공용)" }
            Write-Host ("- {0} | {1} | {2}" -f $_.itemId, (좌측정렬 $PaddingWidth $JobInfo), $_.itemName);
        }
        Write-Host ("`n검색결과 : {0} 행`n" -f ($Response.rows).Count);
    }
}

# 여러 아이템을 특정 index로 검색하는데 사용. 예) 최저가 검색
function 횡검색($Index, [hashtable]$Table) {
    # 파라미터 검사
    if(($index -lt 1) -or ($index -gt 20)) {
        throw "'횡검색'의 인덱스는 1 이상 20 이하의 숫자여야 합니다.";
    }

    # 목록을 하나씩 읽어 데이터 요청
    $List = [System.Collections.Generic.List[object]]::new();
    foreach ($i in 0..($Table.Count -1)) {
        $Value = $Table[$i];

        # id로 판단하는 경우
        if(($Value -match "^[0-9a-f]+$") -and ($Value.Length -ge 20)) {
            if($Value.Length -eq 32) {
                $AddParams = @{ itemId = $Value; }
                $Response = 서버요청 $Config3 $AddParams;
            } else {
                throw "'횡검색'에 정확한 id를 입력하세요. id는 32글자의 0~9,a~f 문자의 조합입니다.";
            }
        
        # name으로 판단하는 경우
        } else {
            $AddParams = @{ itemName = 인코딩($Value); }
            $Response = 서버요청 $Config3 $AddParams;
        }

        # 요청결과 담기
        if($Response.rows.Count -eq 0) {
            Write-Host ("* {0}번째 아이템(:{1})은 경매장에 없습니다." -f $i, $Value) -ForegroundColor Yellow;
            [void]$List.Add([PSCustomObject]@{ });
        } else {
            [void]$List.Add($Response.rows[$index - 1]);
        }
    }

    # 결과 반환
    return $List;
}

# 단일 아이템의 현재가격 및 판매이력을 확인하는데 사용
function 종검색($Value) {
    # id로 판단하는 경우
    if(($Value -match "^[0-9a-f]+$") -and ($Value.Length -ge 20)) {
        if($Value.Length -eq 32) {
            $AddParams = @{ itemId = $Value; }
            $Response1 = 서버요청 $Config4 $AddParams;
            $Response2 = 서버요청 $Config5 $AddParams;
        } else {
            throw "'종검색'에 정확한 id를 입력하세요. id는 32글자의 0~9,a~f 문자의 조합입니다.";
        }

    # name으로 판단하는 경우
    } else {
        $AddParams = @{ itemName = 인코딩($Value); }
        $Response1 = 서버요청 $Config4 $AddParams;
        $Response2 = 서버요청 $Config5 $AddParams;
    }

    # 현재가격 출력 (가장 낮은 금액부터)
    Write-Host "`n[ 현재가격 ]`n";
    $Data1 = $Response1.rows;
    if($Data1.Count -gt 0) {
        # 평균가격
        $JobInfo = if($Data1[0].jobs) { $Data1[0].jobs[0].jobName } else { "(공용)" }
        Write-Host ("평균가격 : {0} 골드 (= '({1}) {2}' 기준)`n" -f (한글단위($Data1[0].averagePrice)), $JobInfo, $Data1[0].itemName);

        # 개별항목
        $Data1 | ForEach-Object {
            $JobInfo = if($_.jobs) { $_.jobs[0].jobName } else { "(공용)" }
            "- {0} | {1} : {2} 개 : {3} 골드 : {4}" -f (좌측정렬 $PaddingWidth $JobInfo), $_.itemName, (한글단위($_.count)), (한글단위($_.unitPrice)), (남은시간($_.expireDate));
        }

        # 행 갯수
        Write-Host ("`n검색결과 : {0} 행" -f $Data1.Count);

    } else {
        Write-Host ("'{0}'은(는) 경매장에 없습니다." -f $Value);
    }

    # 판매이력 출력 (가장 높은 금액부터)
    Write-Host "`n[ 판매이력 ]`n";
    $Data2 = $Response2.rows | Sort-Object -Property unitPrice -Descending;
    if($Data2.Count -gt 0) {
        # 개별항목
        $Data2 | ForEach-Object {
            $JobInfo = if($_.jobs) { $_.jobs[0].jobName } else { "(공용)" }
            "- {0} | {1} : {2} 개 : {3} 골드 : {4}" -f (좌측정렬 $PaddingWidth $JobInfo), $_.itemName, (한글단위($_.count)), (한글단위($_.unitPrice)), $_.soldDate;
        }

        # 행 갯수
        Write-Host ("`n검색결과 : {0} 행" -f $Data2.Count);

    } else {
        Write-Host ("'{0}'에 대한 판매이력이 없습니다." -f $Value);
    }
}

#endregion