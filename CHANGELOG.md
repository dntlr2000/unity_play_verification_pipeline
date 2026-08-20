# Changelog

## Unreleased

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
