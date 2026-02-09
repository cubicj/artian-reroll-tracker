# Artian Reroll Tracker - 기술 참조

> v3.8.2 완료. 세션별 개발 히스토리는 Git log 참조.
> 마지막 갱신: 2026-02-09

---

## 버전 히스토리

### v3.8.2 (2026-02-09)
- 디버깅 로그 제거 (프로덕션 정리)
- lotterySkill, getEm0078_ArtianBonusColor, setWeaponDataCore hook 로그 정리
- 에러 로그만 유지

### v3.8.1 (2026-02-09)
- 🐛 **무기 타입 오인식 버그 수정**
- setWeaponDataCore Hook에서 WeaponData 필드 순회하여 무기 타입 추출
- WeaponData._Rod, _TwinSword 등 무기별 ID 필드에서 0보다 큰 값 찾기
- Lottery Mode에서 복원 보너스 없는 무기도 정상 작동 확인
- 테스트: 조충곤(10) + 랜스(6) + 조충곤(10) 정상 기록

### v3.7.1 (2026-02-06)
- 초기 릴리스 (Grinding Mode + Lottery Mode)

---

## 아키텍처 요약

파일: `artian_reroll_tracker.lua` (571줄)
데이터: `reframework/data/reroll_sessions.json`

### Hook 구조 (7개)

| Hook                         | 대상                                  | 용도                                                                                 |
| ---------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------ |
| `getEm0078_ArtianBonusColor` | `app.GUI080000ArtianStatus`           | Grinding Mode: 보너스 ID 캡처 (args[3] = List\<BONUS_ID>) + 무기 타입 캡처 (args[7]) |
| `setWeaponDataCore`          | `app.GUI080000ArtianStatus`           | 속성/격화 타입 자동 감지 (GUI 텍스트 직접 읽기)                                      |
| `lotterySkill`               | `app.Em0078_ArtianUtil`               | Lottery Mode: Post Hook에서 BonusByCreating → ArtianSkillType 캡처                   |
| `startArtianGrindingAnim`    | `app.GUI080000ArtianStatus`           | Grinding Mode: 기록 트리거 + 애니메이션 스킵 (Action:Invoke → SKIP_ORIGINAL)         |
| `startSkillLotteryAnim`      | `app.GUI080000ArtianStatus`           | Lottery Mode: 기록 트리거 + 애니메이션 스킵                                          |
| `startUpGrade`               | `app.cGUILoopGaugeChangeRequirePoint` | 게이지 애니메이션 스킵                                                               |
| `requestNotifyWindow`        | `app.cGUISystemModuleNotifyWindowApp` | 대화상자 자동 스킵                                                                   |

### 대화상자 자동 스킵 대상

| ID                   | selectedIndex | 설명             |
| -------------------- | ------------- | ---------------- |
| `EQUIP_000`          | 0             | 장비 확인        |
| `EQUIPMENT_0008_15`  | 0             | 장비 확인        |
| `GUI080301_0005_DLG` | 0             | 확인             |
| `GUI080301_0009_DLG` | 1             | "다시 리롤" 선택 |
| `GUI080301_0010_DLG` | 1             | "다시 리롤" 선택 |

---

## 핵심 기술 결정

### 1. Grinding Mode 데이터 캡처 (v3.0.0)

문제: "다시 리롤" 선택 시 SaveData.BonusByGrinding이 업데이트되지 않아 동일한 값만 기록됨.
해결: `getEm0078_ArtianBonusColor` Pre Hook에서 `args[3]` (List\<BONUS_ID>)를 직접 캡처. SaveData 변경 여부와 무관하게 항상 최신 값 포함.

### 2. Lottery Mode 데이터 캡처 (v3.2.0)

문제: 동일하게 "다시 리롤" 시 SaveData.BonusByCreating 미갱신.
해결: `Em0078_ArtianUtil.lotterySkill(cEquipWork)` Post Hook에서 수정된 `BonusByCreating` 값 직접 읽기 → `decode_artian_skill_type()` → `ArtianSkillGroupData`에서 SeriesSkillId/GroupSkillId 매핑.

### 3. 무기/속성/격화 자동 감지 (v3.6.0)

해결: `setWeaponDataCore` Hook에서 GUI 텍스트 직접 읽기.

- `_ArtianCreateTypeText:get_Message()` → 격화 타입 (예: "공격 격화 타입")
- `_PerformanceText:get_Message()` → 속성 (예: "마비속성 타입")
- 로컬라이제이션 불필요, 모든 언어 자동 지원.

### 4. 세션 관리 (v3.7.0)

- Enable 시 "Unknown" 세션으로 시작, 첫 시도에서 `check_and_update_session_weapon()`이 실제 값으로 초기화.
- 매 시도마다 무기 변경 감지 → 자동 세션 종료/시작.

---

## 데이터 구조

### getBonusIdList 반환값 (8개)

```
app.ArtianUtil.getBonusIdList(cEquipWork) → 8개 반환
[1~3]: 생산 보너스 (BonusByCreating 관련 메타데이터)
[4~8]: 게임 UI 복원 강화 5개 슬롯 (BonusByGrinding)
```

### BonusByCreating → ArtianSkillType 디코딩

```
BonusByCreating (uint32) = 3자리 × 3세그먼트
  first  = value % 1000
  second = floor(value / 1000) % 1000
  third  = floor(value / 1000000) % 1000

  asFirst  = floor(first / 10) % 10
  asSecond = floor(second / 10) % 10
  asThird  = floor(third / 10) % 10

  ArtianSkillType = asThird * 100 + asSecond * 10 + asFirst
```

### 스킬 이름 매핑

```
ArtianSkillType → ArtianSkillGroupData._Values에서 조회
  → get_SeriesSkillId() / get_GroupSkillId()
  → app.MessageUtil.getHunterSkillName(skillId) → System.Guid
  → via.gui.message.get(guid) → 로컬라이즈된 이름
```

### JSON 구조

```json
{
  "lastUpdated": "2026-02-06 12:00:00",
  "totalWeapons": 2,
  "currentSession": { ... },
  "weapons": [
    {
      "nickname": "공격 격화 타입 마비속성 타입 한손검",
      "weaponType": 1,
      "weaponTypeName": "한손검",
      "attribute": "마비속성 타입",
      "kagekiType": "공격 격화 타입",
      "mode": "grinding",
      "startTime": "2026-02-05 12:00:00",
      "endTime": "2026-02-05 12:05:00",
      "totalAttempts": 46,
      "attempts": [
        {
          "attemptNum": 1,
          "timestamp": "2026-02-05 12:00:05",
          "bonuses": ["회심률 강화Ⅱ", "예리도/장전 강화Ⅰ", "회심률 강화 EX", "기초 공격력 강화Ⅱ", "기초 공격력 강화 EX"]
        }
      ]
    }
  ]
}
```

Lottery Mode attempt 구조:

```json
{
  "attemptNum": 1,
  "timestamp": "...",
  "skills": { "series": "갑충의 알림", "group": "거극룡의 묵시록" }
}
```

---

## SDK 참조 파일

```
C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterWilds\sdk_ida\app\
├── ArtianUtil.hpp
├── ArtianDef.hpp            (BONUS_ID enum)
├── Em0078_ArtianUtil.hpp    (lotterySkill)
├── GUI080000ArtianStatus.hpp
├── savedata\cEquipWork.hpp  (BonusByGrinding, BonusByCreating)
└── HunterSkillUtil.hpp
```

---

## 사용자 피드백 및 개선 계획

> 마지막 갱신: 2026-02-09

### 🔴 긴급 버그

#### 격화 업그레이드 시 무기 오인식

**보고**: JaSon (디시인사이드, 2026-02-06)
**상태**: 🟢 **해결됨 (v3.8.1)** - 추가 테스트 권장

**문제**:
- 번개 태도에서 격화 업그레이드 → 스킬재부여 진입 시 쌍검으로 오인식
- 격화 올릴 때 weapon count 1 → 스킬재부여 진입 시 count 2 (잘못된 세션)
- Pastebin 로그: https://pastebin.com/dnvsFA8W

**재현 시나리오**:
1. Enable 상태로 아티어 격화 업그레이드 수행
2. 격화 완료 후 나가기 (weapon count = 1)
3. 스킬재부여로 재진입 (weapon count = 2, 무기 타입 변경 감지)

**근본 원인 (v3.8.1에서 수정)**:
- Lottery Mode에서 무기 타입을 잘못 추출하여 오인식 발생
- `bonusColorMethod`가 Lottery Mode에서 호출되지 않아 무기 타입 미캡처

**해결 방법 (v3.8.1)**:
- `setWeaponDataCore` Hook에서 WeaponData 필드 순회
- `_Rod`, `_TwinSword` 등 무기별 ID 필드에서 0보다 큰 값을 찾아 무기 타입 추출
- 복원 보너스 유무와 무관하게 정상 작동
- 테스트 완료: 조충곤(10) + 랜스(6) + 조충곤(10) 정상 기록

**남은 이슈**:
- 격화 업그레이드 특수 시나리오 추가 테스트 필요
- 격화 타입 변경 시 세션 전환 동작 확인 필요

---

### 🟡 주요 개선 사항

#### 1. 격화 타입 선택적 그룹화

**요청**:
- ㅇㅇ, 종팔이 (디시인사이드)
- Luxiel (Nexus Mods, 2026-02-06)

**상태**: ✅ 합의됨 (v3.8.0)

**내용**:
- 격화 타입은 리롤 테이블에 영향을 주지 않음
- 무기 타입 + 속성만으로 그룹화하는 옵션 추가

**예시** (Luxiel):
> 용 속성 조충곤을 회심 격화로 6번 리롤 → 속성 격화로 변경하여 리롤 시,
> 속성 격화의 첫 번째 리롤이 attemptNum 7이 되어야 함

**구현 계획**:
- Config 옵션: `groupByKagekiType` (기본값: false)
- false 시: 무기 타입 + 속성만으로 세션 구분
- true 시: 기존 동작 유지 (무기 + 속성 + 격화)

#### 2. 세션 복원 기능

**요청**: Luxiel (Nexus Mods, 2026-02-06)
**상태**: ✅ 합의됨 (v3.8.0)

**문제**:
- 게임 재시작 시 `currentSession` 복원 안 됨
- 저장 안 하고 종료(세이브 스컴) 시 진행 중인 세션 데이터 손실

**해결 방향**:
1. `currentSession`을 `weapons` 배열에 임시 항목으로 저장 (`isIncomplete: true`)
2. 게임 재시작 시 `isIncomplete` 항목 복원 → `currentSession`으로 이동
3. 세션 완료 시 `isIncomplete` 플래그 제거

**임시 해결책** (v3.7.1):
- 게임 종료 전 트래커 Disable 권장

---

### 🟢 향후 계획

#### JSON → UI 웹앱

**요청**: JaSon (디시인사이드, 2026-02-06)
**상태**: 🔄 개발 중

**현황** (팩토리오):
- UI 프로토타입 제작 완료
- 배포 방식 및 퀄리티 개선 중

**기능**:
- JSON 파일 업로드 → 시각화된 리롤 히스토리
- `attemptNum`, `group`, `series` 필터링
- 엑셀 내보내기 (임시: 수동 복사 가능)

#### 스킬/강화 필터링

**요청**: Aquapigeon (Nexus Mods, 2026-02-06)
**상태**: 📝 검토 중

**내용**:
> 500번의 리롤 중 "고어 마갈라 + 주인님의 영혼" 조합이 있다는 건 알지만
> 정확히 몇 번째인지 모를 때 필터링하여 찾고 싶음

**기술적 고민**:
- 모드 내 UI에 구현 vs 웹앱에 구현
- 필터 조건 복잡도 (AND/OR, 부분 매칭 등)

---

### ❓ FAQ (자주 묻는 질문)

#### Q1. 이 모드가 뭘 하는 건가요?

**A**: 세이브 스컴을 위한 리롤 기록 도구입니다.
- 리롤 결과를 자동으로 JSON에 기록
- 애니메이션/대화상자 스킵으로 속도 향상
- 리롤 결과를 **조작하지 않음** (Tracker, not Editor)

**출처**:
- Ryo4Athena (Nexus Mods): "원하는 스킬을 선택할 수 있는 게 아니면 뭐가 다른가요?"
- Luxiel 답변: "리롤을 추적하는 거지 변경하는 게 아닙니다"

#### Q2. 다른 모드(대화상자 스킵 등)와 충돌하나요?

**A**: 충돌 가능성 낮음, 테스트 권장
- 같은 대화상자를 스킵하는 모드와 중복 가능성 있으나 문제 없을 것으로 예상
- 실제 사용 후 이슈 발생 시 보고 바람

**출처**: JaSon (디시인사이드, 2026-02-06)

#### Q3. 리롤 테이블은 무기별로 독립적인가요?

**A**: 불명확 - 추가 조사 필요
- 같은 무기의 다른 속성끼리는 테이블 공유 (확인됨)
- 다른 무기 타입 간 테이블 공유 여부는 미확인
- 세이브 데이터에서 테이블 포인터 발견 안 됨 (런타임 또는 시드 기반 추정)

**출처**: Luxiel (Nexus Mods, 2026-02-06)

---

### 📊 피드백 통계

**출처별 분포**:
- 디시인사이드: 9명 (해골올챙이, JaSon, 모리바1, ㅇㅇ, 종팔이 등)
- Nexus Mods: 4명 (hfeiowjmopgefcefc, Aquapigeon, Luxiel, Ryo4Athena)

**긍정적 평가**:
- "지금까지 써본 방법 중 제일 좋음" (JaSon)
- "이 게임 최고의 모더 중 한 명" (hfeiowjmopgefcefc)
- "애니메이션 제거만으로도 엄청난 도움" (Luxiel)
