# 배 가라앉히지 마 (Don't Sink the Boat!) — Roblox 파티 게임

이 저장소는 `docs/`의 개발 계획서(31단계)를 따라 만든다. 혼자 만드는 프로젝트이고, 코드는 Claude Code 같은 AI 도구가 많이 쓴다.

## 먼저 읽을 것

1. `docs/README.md` — 전체 지도와 읽는 순서
2. `docs/01-rules.md` — 규칙 기준서. 규칙마다 번호가 있다
3. `docs/02-config.md` — 수치. 코드에 쓰는 숫자는 여기 키 이름뿐이다
4. `docs/03-architecture.md` — 폴더 틀, 서버 모듈, 원격 이벤트, 버튼 처리 순서

## 일하는 방식

- **한 번에 한 단계.** `docs/S??-*.md` 하나만 연다. 그 단계의 "지킬 규칙", "쓰는 수치", "하지 않는 것"을 따르고, "완료 확인"을 전부 통과한 뒤에만 다음 단계로 간다.
- 단계 파일에 없는 것을 미리 만들지 않는다. 문서에 없어서 정해야 하는 것이 생기면 멈추고 묻는다.
- 규칙을 바꾸고 싶으면 코드부터 고치지 않는다. 순서는 `docs/01-rules.md` 첫머리에 있다: 기준서 → 시험(S03) → `docs/build.py` → 코드 → 완료 확인 → 기획 문서.
- `docs/`의 표는 `docs/build.py`가 만든다. 규칙이나 수치를 고친 뒤에는 `python3 docs/build.py docs docs`로 다시 채우고 검사한다.

## 어기면 안 되는 것 (docs/03-architecture.md의 원칙 여섯)

1. 판정은 서버가 한다. 클라이언트는 "눌렀다"만 보낸다.
2. 숨은 값(한계, 종 간격, 다음 종 시각)은 서버 스크립트의 지역 변수에만 둔다. 속성, 값 객체, 원격 이벤트 인자, ReplicatedStorage에 두지 않는다.
3. 판정 함수 안에서는 `task.wait`, 트윈 완료 대기, 원격 호출 응답 대기를 하지 않는다.
4. 봇도 사람과 같은 서버 함수를 부른다. 봇용 판정을 따로 만들지 않는다.
5. 숫자는 `Shared/Config`의 키로만 쓴다.
6. 규칙의 판정은 `Shared/Rules`의 순수한 모듈에 두고 S03의 시험을 붙인다. 이 모듈은 `workspace`, `game`, `Instance`를 만지지 않는다.

## 파일 규칙

- 모든 스크립트는 `--!strict`로 시작한다.
- 파일 이름의 끝이 종류를 정한다: `이름.luau` 모듈, `이름.server.luau` 서버 스크립트, `이름.local.luau` 로컬 스크립트.
- 스크립트에 속성이나 태그를 달지 않는다(Script Sync가 무시한다).

## 디스크와 Studio의 대응 (Script Sync)

| 디스크 | Studio |
| --- | --- |
| `src/Shared/` | `ReplicatedStorage/Shared` |
| `src/Server/` | `ServerScriptService/Server` |
| `src/Client/` | `StarterPlayer/StarterPlayerScripts/Client` |

`Remotes`, `Map`, `Hud` 같은 모형과 화면은 Studio에만 있고 디스크에 없다. 이 폴더들은 동기화하지 않는다. 그런 것을 만들거나 고치려면 Studio에서 하거나, Studio MCP가 연결돼 있을 때 그 도구로 한다.

## 시험

S03부터는 Studio에서 서버를 켤 때 `DevTools`의 `DEBUG_RUN_TESTS`가 켜져 있으면 규칙 시험이 돈다. 하나라도 실패하면 그 단계는 끝난 것이 아니다.
