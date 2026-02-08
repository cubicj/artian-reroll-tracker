# Artian Reroll Tracker - 기술 참조

> v3.7.1 완료. 세션별 개발 히스토리는 Git log 참조.
> 마지막 갱신: 2026-02-06

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
