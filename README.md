# Unity Play Verification Pipeline

Unity Play Verification Pipeline은 Unity 원본 프로젝트를 수정하지 않고 외부 격리 복사본에서 Editor PlayMode 테스트와 검토 가능한 source-only 시나리오를 실행하는 독립 파이프라인이다. 이 저장소는 `unity_agent_pipeline`이나 전역 Doctor/Baseline Skill이 없어도 설치·실행·테스트할 수 있다.

현재 저장소 버전과 `$unity-play-verification` Skill 버전은 모두 `0.2.0`이다. Skill은 명시 호출 전용이며 `allow_implicit_invocation: false`를 유지한다.

## 책임과 구조

~~~text
unity_play_verification_pipeline/
├─ skills/codex/unity-play-verification/
│  ├─ config/                  # exact Unity/Test Framework 호환성 registry
│  ├─ harness/                 # 격리 Scenario C# 실행 계약
│  ├─ scripts/
│  │  ├─ invoke-unity-play-verification.ps1
│  │  ├─ lib/                  # Play 전용 XML/log/scenario 판정
│  │  └─ vendor/               # 고정된 Doctor·공용 안전 모듈
│  └─ templates/minimal-scenario/
├─ scripts/                    # Play 하나만 설치하는 독립 설치기
├─ modules/                    # vendored dependency 출처·해시·갱신 정책
├─ schemas/                    # result/scenario/compatibility schema 1.0.0
├─ compatibility/              # 승인 registry 운영 정책
├─ tests/
│  ├─ fixtures/
│  └─ acceptance/
└─ docs/
~~~

공용 런타임 사본을 최상위 `modules`가 아니라 Skill 내부 `scripts/vendor`에 둔 이유는 설치된 Skill symbolic link 하나만으로 모든 실행 파일을 찾게 하기 위해서다. 최상위 `modules`는 사본의 provenance와 고정 해시를 관리한다.

## 설치

먼저 변경 계획만 확인한다.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-unity-play-verification-skill.ps1 -WhatIf
~~~

확인 후 설치한다.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-unity-play-verification-skill.ps1
~~~

설치기는 `$HOME\.agents\skills\unity-play-verification` 하나만 다룬다. 같은 source를 가리키는 symbolic link 또는 junction은 그대로 둔다. symbolic-link 권한이 없는 Windows에서는 정확한 로컬 target의 junction으로 폴백하며, 실제 디렉터리·파일·다른 target의 link는 덮어쓰거나 삭제하지 않는다.

## 직접 실행

프로젝트의 기존 Editor PlayMode 테스트 전체를 실행한다.

~~~powershell
$runner = ".\skills\codex\unity-play-verification\scripts\invoke-unity-play-verification.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -ProjectRoot "C:\path\to\UnityProject"
~~~

선택 실행은 `-TestFilter`, `-TestCategory`, `-AssemblyNames`에 세미콜론 문자열을 전달한다. 임의 Unity 인수는 받지 않는다.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
    -ProjectRoot "C:\path\to\UnityProject" `
    -TestFilter "Game.Tests.Smoke;Game.Tests.UI"
~~~

격리 시나리오 모드는 외부 bundle을 사용한다.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
    -ProjectRoot "C:\path\to\UnityProject" `
    -ScenarioBundlePath "C:\external\reviewed-scenario"
~~~

`ScenarioBundlePath`는 테스트 선택 파라미터와 함께 사용할 수 없다. 정상 stdout은 JSON 문서 하나이며 같은 문서가 외부 `result.json`에 저장된다. 기본 artifact root는 `%TEMP%\upv`이고 자동 정리하지 않는다.

## 판정 경계

- `PLAY_VERIFIED`: 선택된 Editor PlayMode 테스트 또는 named scenario가 1개 이상 모두 실행·통과했고 필수 증거와 원본 무결성이 일치함
- `PLAY_FAILED`: 완결된 XML/log/process 증거에서 compilation, test, crash 또는 scenario 실패가 확인됨
- `VERIFICATION_BLOCKED`: 안전·호환성·timeout·누락·불일치·0개·Skip/Inconclusive 조건을 충족하지 못함
- `ORIGINAL_PROJECT_CHANGED`: 원본 copy-set 또는 허용 범위 밖 Git metadata가 변경됨

`PLAY_VERIFIED`는 Player Build, 실제 장치 입력, OS 좌표 자동화, 전체 gameplay, 장기 성능, 재미·조작감·미적 품질 또는 release readiness를 의미하지 않는다.

## 검증

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installer-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\acceptance\run-real-unity-acceptance.ps1
~~~

세부 계약은 [Skill 문서](docs/skills/unity-play-verification.md), 독립화 구조는 [아키텍처](docs/architecture.md), 고정 공용 코드 출처는 [vendored dependencies](modules/VENDORED_DEPENDENCIES.md), 실제 Unity 승인 범위는 [승인 기록](docs/validation/unity-play-verification-real-unity-acceptance.md)을 따른다.
