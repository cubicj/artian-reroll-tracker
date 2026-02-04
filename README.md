# Artian Reroll Tracker

거극(Gogmazios) 아티어 무기 복원 강화 리세마라 추적 모드

## 기능

- 복원 강화 시 나오는 5개 보너스 옵션 자동 기록
- 무기별 시도 번호 자동 관리
- JSON 파일로 자동 저장 (`reframework/data/reroll_sessions.json`)
- 한글 보너스 이름 표시

## 사용 방법

### 1. 모니터링 시작
1. 게임에서 Insert 키 → "Artian Reroll Tracker" 메뉴
2. "Start Monitoring" 클릭
3. 복원 강화 진행

### 2. 자동 기록
- 복원 강화 실행 시마다 자동으로 기록됨
- 무기를 바꾸면 시도 번호 자동 리셋
- 같은 무기 = 시도 번호 계속 증가 (#1, #2, #3...)

### 3. 모니터링 종료
- "Stop Monitoring" 클릭
- 세션 데이터가 JSON에 자동 저장

### 4. 데이터 분석
- JSON 파일 위치: `C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterWilds\reframework\data\reroll_sessions.json`
- 파이썬/TypeScript 등으로 분석 가능

## JSON 출력 형식

```json
{
  "savedAt": "2026-02-02 18:30:00",
  "currentSession": {
    "startTime": "2026-02-02 18:00:00",
    "endTime": "2026-02-02 18:30:00",
    "attempts": [
      {
        "attemptNum": 1,
        "weaponIndex": 414,
        "timestamp": "2026-02-02 18:05:12",
        "gameUIBonuses": [
          "회심률 강화Ⅱ",
          "예리도/장전 강화Ⅰ",
          "회심률 강화 EX",
          "기초 공격력 강화Ⅱ",
          "기초 공격력 강화 EX"
        ],
        "bonusByGrinding": 16009017007010,
        "bonusSlots": [16, 9, 17, 7, 10],
        "grindingNum": 5
      }
    ]
  },
  "history": []
}
```

## 주요 필드

- `attemptNum`: 시도 번호 (무기별)
- `weaponIndex`: 장비 박스 인덱스 (0~2399)
- `gameUIBonuses`: 게임 UI에 표시되는 5개 보너스 (한글)
- `bonusByGrinding`: 원본 uint64 값
- `bonusSlots`: 15자리 파싱 결과 (참고용)

## 워크플로우

1. 복원 강화할 무기 준비
2. Start Monitoring
3. 재료 소진까지 연속 강화
4. Stop Monitoring
5. JSON 파일 확인
6. 원하는 옵션 조합을 찾으면 해당 시도 번호 확인
7. 세이브 롤백 후 해당 시도 번호까지 강화

## 주의사항

- 모니터링 중에는 게임 UI에서 G키로 직접 강화 실행 필요
- 세이브하지 않고 종료하면 롤백됨 (리세마라 원리)
- JSON 파일은 게임 종료 시까지 유지됨

## 버전

v1.0.0 - 기본 추적 시스템

## 제작

JCubic
