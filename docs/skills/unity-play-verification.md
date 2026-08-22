# Unity Play Verification 0.3.0

`$unity-play-verification`은 원본 Unity 프로젝트를 Unity에 열지 않고, 외부 격리 복사본에서 선택한 Editor PlayMode 테스트 또는 검토 가능한 source-only 시나리오를 실행하는 명시 호출 전용 Skill이다.

## 호출 정책

- 요청에 literal `$unity-play-verification` 이름이 있어야 한다.
- Doctor나 Baseline의 후속 단계라는 이유만으로 자동 실행하지 않는다.
- `$unity-baseline-verification`을 호출하거나 Baseline 결과 계약을 확장하지 않는다.
- Unity, Unity Hub, package, module 또는 Test Framework를 설치·업데이트하지 않는다.
- 원본 프로젝트에는 파일, 로그, Library 또는 테스트 오버레이를 만들지 않는다.

## 검증 모드

### 기존 PlayMode 테스트

기본 모드는 대상 프로젝트가 이미 가진 모든 PlayMode 테스트를 실행한다.

~~~powershell
$runner = ".\skills\codex\unity-play-verification\scripts\invoke-unity-play-verification.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -ProjectRoot "E:\Unity\MyProject"
~~~

선택자는 각각 하나의 process argument로 전달된다. 여러 값은 Unity Test Framework 계약에 맞는 세미콜론 문자열을 사용한다.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
    -ProjectRoot "E:\Unity\MyProject" `
    -TestFilter "Game.Tests.Smoke;Game.Tests.UI" `
    -TestCategory "Fast;Regression" `
    -AssemblyNames "Game.PlayMode.Tests"
~~~

### 격리 시나리오 오버레이

시나리오 모드는 외부 bundle을 검증한 뒤 격리 복사본의 예약 경로 `Assets/__UnityPlayVerification`에만 harness와 source를 주입한다.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
    -ProjectRoot "E:\Unity\MyProject" `
    -ScenarioBundlePath "E:\CodexValidation\example-scenario"
~~~

`ScenarioBundlePath`는 `TestFilter`, `TestCategory`, `AssemblyNames`와 함께 사용할 수 없다. 시나리오 manifest가 정확한 test filter를 소유한다.

## 공개 파라미터

| 파라미터 | 기본값 | 의미 |
| --- | --- | --- |
| `ProjectRoot` | 현재 작업 디렉터리 | 정확한 Unity 프로젝트 루트 |
| `UnityExecutable` | 자동 탐색 | 선언 버전과 정확히 일치해야 하는 `Unity.exe` override |
| `ArtifactsRoot` | `%TEMP%\upv` | 원본 밖에 둘 보존용 artifact 부모 |
| `TimeoutSeconds` | `1800` | Unity root process 제한 시간 |
| `TestFilter` | 없음 | 세미콜론 기반 Test Framework filter |
| `TestCategory` | 없음 | 세미콜론 기반 category 선택 |
| `AssemblyNames` | 없음 | 세미콜론 기반 test assembly 선택 |
| `ScenarioBundlePath` | 없음 | 외부 source-only 시나리오 bundle |
| `Pretty` | false | stdout/result.json 들여쓰기 여부 |

임의 Unity 인자는 받을 수 없다.

## 실행 계약

Verifier는 bundled Doctor scanner를 직접 실행해 다음을 확인한다.

- Doctor schema `1.1.0`
- scanner `0.2.1`
- Unity 프로젝트 판정
- 현재 verifier fingerprint와 일치하는 안정된 Doctor fingerprint
- Doctor blocker 부재

이 scanner는 Skill 내부에 고정된 사본이며 외부 `$unity-project-doctor` 설치를 찾거나 호출하지 않는다. Baseline verifier도 실행하거나 수정하지 않는다.

Unity 실행 파일은 다음 순서로만 확인한다.

1. `-UnityExecutable`
2. process 환경의 `UNITY_EDITOR_PATH`
3. process 환경의 `UNITY_HUB_EDITOR_ROOT`
4. Program Files
5. Program Files (x86)

선택된 파일은 exact ProductVersion token, 유효한 Authenticode 상태, Unity Technologies signer, SHA-256을 모두 충족해야 한다. Hub 실행, registry/drive 재귀 검색, 근접 버전 대체, 설치 또는 업데이트는 없다.

실행 중인 Unity가 있으면 모든 still-running PID의 command line에서 단 하나의 절대 `-projectPath`를 안전하게 판독한다. 대상 원본 프로젝트를 연 Editor는 차단한다. 다른 프로젝트의 Editor는 허용하지만, 명령줄을 읽거나 정확히 연관 지을 수 없으면 fail-closed로 차단한다.

Test Framework provenance는 Unity 시작 전에 다음을 모두 만족해야 한다.

- `Packages/manifest.json`에 exact version 문자열 선언
- `Packages/packages-lock.json`의 같은 exact version
- compatibility 1.2 항목과 동일한 lock source: `registry` 또는 `builtin`
- `registry`이면 canonical origin `https://packages.unity.com`; `builtin`이면 registry URL 부재
- `com.unity.test-framework`를 가로챌 custom scoped registry 부재
- exact Unity ProductVersion, Unity Technologies Authenticode, 승인된 Unity.exe SHA-256

Local/`file:`, embedded, git, tarball, 승인 항목과 다른 source, 누락 또는 모호한 source는 차단한다. Unity 종료 뒤에는 격리본의 manifest/lock을 다시 검증하고 실행 전 provenance와 비교한다. 이어서 `Library/PackageCache` 아래 정확히 하나의 실제 package를 찾고, reparse point 없이 정렬된 상대 경로·파일 길이·raw SHA-256을 사용한 두 번의 연속 안정 tree snapshot이 compatibility registry의 승인 hash와 일치해야 한다.

현재 source-specific Editor/package identity로 승인된 조합은 다음과 같다.

| Unity | Test Framework | 승인 source | 상태 |
| --- | --- | --- | --- |
| `2022.3.62f3` | `1.1.33` | Unity registry | `APPROVED` |
| `6000.0.69f1` | `1.6.0` | exact Editor-builtin | `APPROVED` |
| `6000.5.3f1` | `1.7.0` | exact Editor-builtin | `APPROVED` |

Unity 6의 builtin 항목은 임의 builtin package를 허용하지 않는다. 각 항목은 실제 signed Editor 승인 실행에서 얻은 Unity.exe SHA-256과 resolved package tree SHA-256을 함께 고정한다.

추가 조합은 parser fixture와 실제 서명 Unity 승인 기록을 함께 추가하기 전에는 실행되지 않는다.

## 격리와 Unity 인자

Doctor/Baseline copy-set과 같은 범위를 짧은 외부 session의 `p` 디렉터리에 복사한다. `Library`, `Temp`, `Logs`, `UserSettings`, `.git`, `.agents`, `.codex`, IDE metadata와 빌드 산출물은 복사하지 않는다. 각 파일을 snapshot 길이와 SHA-256으로 확인하고 복사본 fingerprint가 원본과 정확히 일치해야 한다.

Unity에는 고정된 인자만 전달된다.

- `-batchmode`
- `-forgetProjectPath`
- `-runTests`
- `-projectPath <isolated-copy>`
- `-testPlatform PlayMode`
- `-testResults <external-xml>`
- `-logFile <external-editor-log>`
- `-upmLogFile <external-upm-log>`
- 선택 모드에 필요한 단일 selector 또는 verifier-owned scenario 인자

`-nographics`, `-quit`, `-runSynchronously`, `-executeMethod`, `-accept-apiupdate`, `-ignorecompilererrors`는 금지한다. 프로세스는 suspended 상태에서 kill-on-close Job Object에 먼저 연결한 뒤 재개한다. Timeout 또는 0개 active process를 증명하지 못한 상태는 차단한다. 명확한 nonzero 실패에서만 루트 종료 후 남은 자식을 Job Object가 성공적으로 종료하고 0개를 증명한 경우를 경고로 기록하며, 성공 후보의 비정상 자식 종료는 계속 차단한다. 안정된 package snapshot과 나머지 필수 증거도 그대로 요구한다.

## 시나리오 bundle 계약

Bundle에는 root `manifest.json`, `.asmdef`, `.cs`만 있을 수 있다. DLL, executable, native plugin, 다른 JSON, reparse point, 원본 내부 경로와 경로 이탈은 차단한다. 모든 파일의 길이와 SHA-256 및 canonical tree SHA-256을 결과에 기록한다.

Manifest schema는 `schemas/unity-play-scenario-1.0.0.schema.json`이다.

~~~json
{
  "schemaVersion": "1.0.0",
  "scenarioId": "player-smoke",
  "displayName": "Player movement smoke",
  "testFilter": "Game.PlayVerification.PlayerSmokeTests.Run",
  "timeoutSeconds": 120,
  "requiresGraphics": true,
  "expectedScenes": ["Assets/Scenes/Game.unity"],
  "expectedAssertionIds": ["player-moved", "hud-visible"],
  "screenshotIds": ["gameplay-frame"]
}
~~~

Test assembly는 `TestAssemblies`를 선언하고 `UnityPlayVerification.Harness`를 참조해야 한다. 시나리오는 다음 계약을 구현한다.

~~~csharp
public interface IPlayVerificationScenario
{
    string ScenarioId { get; }
    IEnumerator Execute(PlayVerificationContext context);
}
~~~

`PlayVerificationContext`는 Scene 로드, 프레임 대기, timeout 조건 대기, assertion 기록, 명명된 PNG 캡처를 제공한다. 캡처는 카메라를 1280×720 RenderTexture로 렌더링해 verifier-owned 외부 경로에 쓴다. 영수증의 scenario ID, Scene 집합, assertion ID 집합, capture ID 집합과 경로가 manifest와 정확히 일치해야 한다.

새 Input System이 이미 있는 프로젝트는 test device와 event injection을 사용할 수 있다. Legacy Input은 기존 test seam 또는 공개 gameplay API를 호출한다. OS 키보드·마우스·focus·창 좌표 자동화는 하지 않는다.

## 결과와 판정

정상 stdout은 schema `1.0.0` JSON 문서 하나뿐이며, 동일한 문서를 외부 `result.json`에 저장한다. 결과에는 Doctor, compatibility의 preflight/post-run provenance와 package identity, Unity trust, selection, process control, isolation, artifacts, NUnit, Editor.log, scenario/captures, 원본 및 Git 무결성, verification scopes, warnings, failures, blockers와 evidence가 있다.

검증 scope 상태는 `NOT_VERIFIED`, `VERIFIED_SUCCESS`, `VERIFIED_FAILURE`, `BLOCKED`만 사용한다.

| 최종 상태 | 의미 |
| --- | --- |
| `ORIGINAL_PROJECT_CHANGED` | 원본 copy-set 또는 허용 범위 밖 Git metadata가 변경됨 |
| `VERIFICATION_BLOCKED` | 안전·호환성·timeout·완결성·0개·Skip/Inconclusive·필수 artifact 조건이 충족되지 않음 |
| `PLAY_FAILED` | 완결된 XML/log/process 증거에서 compile, test, crash 또는 scenario 실패가 확인됨 |
| `PLAY_VERIFIED` | 선택 테스트 또는 시나리오가 1개 이상 모두 실행·통과하고 필수 증거와 무결성이 일치함 |

최종 우선순위는 위 표 순서다. 종료 코드만으로 통과를 판정하지 않으며 NUnit XML, Editor.log, Job Object 종료, 원본/Git 무결성을 함께 사용한다.

`PLAY_VERIFIED` 주장은 선택한 Editor PlayMode 테스트 또는 named scenario에 한정된다. `playerBuild`는 항상 `NOT_VERIFIED`다. 실제 장치 입력, 전체 게임 품질, 네트워크 다중 클라이언트, 성능 장기 측정, 재미·조작감·미적 품질, 릴리스 준비 상태를 의미하지 않는다. PNG는 존재·크기·SHA-256만 자동 검증하고 픽셀 내용으로 합격 여부를 바꾸지 않는다.

## 위협 모델

Source-only 검증은 보안 sandbox가 아니다. 프로젝트 코드와 scenario C#은 Unity와 동일한 사용자 권한으로 실행된다. 보증 범위는 검토 가능한 로컬 source에 대해 승인된 Editor/package toolchain과 증거 완결성을 확인하는 데 한정한다. Fully malicious Unity project의 동일 사용자 파일 접근, 외부 artifact 위조 또는 OS 수준 격리를 방지한다고 주장하지 않는다. Post-run package hash는 합격 승격을 보호하지만 변조 코드의 사전 실행 자체를 sandbox하지 않는다.

## Artifact 보존

각 session은 외부 root 아래 다음 근거를 보존하고 자동 정리하지 않는다.

- 격리 프로젝트 복사본
- Doctor JSON과 stderr
- Editor.log와 UPM log
- Unity stdout/stderr
- NUnit XML
- scenario receipt와 PNG
- 최종 result.json

## 검증

Unity 없이 실행하는 fixture/contract suite:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installer-tests.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installer-tests.ps1
~~~

설치된 실제 서명 Unity를 사용하는 승인 suite:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\acceptance\run-real-unity-acceptance.ps1
~~~

실제 승인 suite는 개발자용이며 CI에서 실행하지 않는다. 요청된 18-case 재검증과 추가 scenario compile-failure 결과, 그리고 두 Unity 6000 조합의 source-policy 차단은 [Unity Play Verification 실제 Unity 승인 기록](../validation/unity-play-verification-real-unity-acceptance.md)에 있다.
