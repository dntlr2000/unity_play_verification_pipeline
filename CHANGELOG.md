# Changelog

## Unreleased

- Test Framework trust now requires exact source-specific provenance before Unity and matching post-run provenance plus deterministic resolved-package identity before any `PLAY_VERIFIED` promotion.
- Preserved immutable compatibility schemas 1.0.0 and 1.1.0, then added schema 1.2.0 with pinned Unity.exe SHA-256 and separate official-registry versus Editor-builtin contracts.
- Reapproved `6000.0.69f1 + 1.6.0` and `6000.5.3f1 + 1.7.0` as exact signed-Editor/builtin package identities without treating builtin content as registry content.
- Fixed malformed NUnit XML compilation-scope promotion, added stable long-path package hashing, and distinguished verified Job Object termination from unproven process-tree exit.
- Added provenance/content-identity, final-precedence, artifact-boundary, overlay-collision, Git-mutation, compilation-failure, and unsigned-fake negative tests under both Windows PowerShell 5.1 and PowerShell 7.x.
- Documented that source-only isolation is not a same-user security sandbox.
- `unity_agent_pipeline`에 구현됐던 Play Verification 0.2.0을 독립 저장소로 추출했다.
- 공개 runner 파라미터, result schema 1.0.0, 최종 상태, verification scope, v0.1 프로젝트 테스트 모드와 v0.2 ScenarioBundle 모드를 유지했다.
- Doctor scanner 0.2.1과 필요한 Baseline 0.2.0 안전 모듈을 해시가 고정된 내부 사본으로 포함했다.
- Play Skill 하나만 안전하게 설치하는 독립 설치기와 standalone fixture/acceptance suite를 추가했다.
- 이 항목은 마이그레이션 작업 기록이며 commit, tag 또는 release를 뜻하지 않는다.

## Component 0.2.0

- source-only ScenarioBundle manifest, overlay, assertion receipt와 PNG artifact 검증
- exact Unity/Test Framework compatibility registry
- 승인 Unity 세 버전의 18-case acceptance 계약

## Component 0.1.0

- 외부 격리 복사본에서 기존 Editor PlayMode 테스트 실행
- NUnit XML, Editor.log, exit code, Job Object와 원본/Git 무결성 결합 판정
