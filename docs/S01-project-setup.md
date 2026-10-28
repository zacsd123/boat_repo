# S01. 도구와 프로젝트 틀

- **묶음**: 준비
- **앞 단계**: 없음
- **크기(어림)**: 작음
- **끝나면**: 계정과 편집 도구가 준비되어 있고, 빈 플레이스에 폴더 틀이 있으며, 서버 1개와 클라이언트 4개로 띄우면 같은 크기의 네 캐릭터가 걸어 다닌다.

## 지킬 규칙

<!--RULES: JN-6-->

| 번호 | 규칙 |
| --- | --- |
| JN-6 | 서버 정원은 8명이다. 9번째 사람은 다른 서버로 간다. |

<!--/RULES-->

## 쓰는 수치

<!--CONFIG: SERVER_MAX_PLAYERS-->

| 키 | 값 | 뜻 |
| --- | --- | --- |
| `SERVER_MAX_PLAYERS` | 8 | 서버 정원(명) |

<!--/CONFIG-->

## 만들 것

1. **계정 먼저.** Roblox 계정의 연령 확인을 끝낸다. 설정 ⟩ 계정 정보(Account info)에서 얼굴 연령 추정(카메라가 있는 폰이 편하다) 또는 신분증으로 한다. 공식 문서의 게시 조건 목록에 "새 게임 게시"가 들어 있어 첫 게시 때 요구될 수 있고, 친구에게 여는 S16에서는 반드시 필요하다. 보통 몇 분이면 끝나지만, 얼굴 추정이 틀리게 나오면 신분증으로 다시 해야 하니 가장 먼저 한다. 2단계 인증도 켠다. 16세 미만에게 열 때(S31) 필요하고, 게임을 가진 계정을 지키는 길이다.
2. **플레이스 만들기.** Roblox Studio에서 Baseplate 템플릿으로 새 플레이스를 만들고 `File ⟩ Publish to Roblox`로 "배 가라앉히지 마"라는 게임으로 올린다. 새 게임은 비공개(Private)로 시작한다. 그대로 둔다. 비공개 게임에는 편집 권한이 있는 사람, 곧 나만 들어갈 수 있다. 폰의 Roblox 앱에 같은 계정으로 들어가면 혼자서 실제 폰으로 시험할 수 있다.
3. **폴더 틀.** `03-architecture.md`의 "폴더 틀"을 그대로 만든다. 스크립트는 이름만 있는 빈 것으로 둔다. `Main`에는 `print("server up")`, `ClientMain`에는 `print("client up")` 한 줄씩만 넣는다.
4. **스크립트를 어디서 고칠지 하나를 고른다.**
   - Studio 편집기만 쓴다: 준비할 것이 없다. 자동 완성과 타입 검사가 처음부터 된다.
   - VS Code(그리고 Claude Code 같은 AI 도구)를 쓴다: 아래를 차례로 한다.
     1. Studio의 `File ⟩ Beta Features`에서 Script Sync를 켜고 Studio를 다시 시작한다. 2026년 10월 기준으로 베타 기능이다.
     2. 탐색기에서 `ReplicatedStorage/Shared`, `ServerScriptService/Server`, `StarterPlayerScripts/Client`를 하나씩 우클릭해 `Script Sync ⟩ Sync to`로 디스크의 한 폴더에 맞춘다.
     3. 디스크에서는 파일 이름의 끝이 종류를 정한다. `이름.luau`는 모듈, `이름.server.luau`는 서버 스크립트, `이름.local.luau`는 로컬 스크립트, 폴더는 폴더다.
     4. VS Code에 Luau Language Server 확장을, Studio에 짝이 되는 Luau Language Server Companion 플러그인을 설치한다. 플러그인이 있어야 확장이 Studio의 구조를 알고 Roblox 함수를 자동 완성한다.
     5. 그 폴더를 Git 저장소로 만든다. 플레이스 파일(`*.rbxl`, `*.rbxlx`)은 `.gitignore`에 넣는다. 맵, 화면, 원격 이벤트는 Script Sync가 맞추지 않으므로 Roblox에 게시해 둔 판(버전 기록)이 그것들의 백업이다.
     6. 이 계획서 폴더를 저장소 안에 함께 둔다(예: `docs/`). AI 도구에게 `01-rules.md`와 `02-config.md`를 따르라고 하기 쉽다.
5. **AI 도구를 Studio에 잇기(고른 경우).** Studio의 Assistant 창에서 `⋯ ⟩ Manage MCP Servers`를 열고 `Enable Studio as MCP server`를 켠다. Assistant 설정의 MCP Servers에서 Quick connect를 펼쳐 쓰는 도구(Claude Code, Claude Desktop, Cursor)를 켠다. 두 프로그램을 다시 시작하고 초록 표시를 확인한다. 연결한 도구는 열린 플레이스를 읽고, 코드를 실행하고, 시험 플레이를 켜고 끄고, 화면을 찍을 수 있다. 플레이스를 바꿀 수도 있으니 믿는 도구만 연결한다.
6. **스크립트 첫 줄.** 모든 스크립트를 `--!strict`로 시작한다. 타입이 안 맞는 곳을 편집기가 알려 준다.
7. **서버 정원.** 게시한 뒤 `File ⟩ Experience Settings ⟩ Places`에서 시작 플레이스의 `⋯ ⟩ Configure Place`를 열어 최대 인원을 `SERVER_MAX_PLAYERS`로 맞춘다.
8. **아바타.** `File ⟩ Avatar Settings`(또는 Avatar 탭)를 연다. 위쪽의 `⋯`에서 아바타 종류를 R15로 고르고, General 탭에서 Consistent Gameplay 프리셋을 고른다. 모든 캐릭터가 같은 키와 같은 충돌 상자를 갖게 된다. 몸 크기가 사람마다 다르면 턱과 화물칸 벽에 걸리는 곳이 달라지고, 상자를 드는 자세와 모자를 붙일 때 일이 는다. 메뉴의 이름과 자리는 바뀔 수 있다.
9. **테스트 방법 두 가지를 한 번씩 해 본다.**
   - 테스트 방식 목록에서 `Server & Clients`를 고르고 클라이언트 4개로 시작한다. 서버 창 1개와 클라이언트 창 4개가 뜬다. 앞으로 거의 모든 "완료 확인"을 이 방식으로 한다. 창이 다섯 개라 컴퓨터가 버거우면 클라이언트 2개로 시작한다.
   - Device Simulator로 화면을 폰 크기로 바꿔 본다.
10. **친구 테스트 준비를 미리 알려 둔다.** S16에서 친구에게 열려면 Audience를 Limited ⟩ Friends(또는 Playtesters)로 바꾸고 콘텐츠 성숙도와 규정 설문을 마쳐야 한다. 평가를 거치기 전의 새 게임은 연령 확인을 마친 16세 이상(과 Trusted Friends)에게 열린다. 그러니 함께 할 친구들에게 각자 계정의 연령 확인을 해 두고, 나와 Roblox 친구를 맺어 두라고 미리 말한다(2026년 10월 기준).

## 하지 않는 것

- 맵, 상자, 규칙은 아무것도 만들지 않는다.
- 프레임워크나 외부 라이브러리를 넣지 않는다. 모듈 스크립트만으로 충분한 크기다.
- 저장 기능(DataStore)을 켜지 않는다. 첫 버전은 아무것도 저장하지 않는다(PR-8).

## 완료 확인

- [ ] 계정의 연령 확인과 2단계 인증이 끝나 있다.
- [ ] Studio를 닫았다 다시 열어 게임을 불러오면 폴더 틀이 그대로 있다.
- [ ] `Server & Clients` 4개로 시작하면 네 캐릭터가 서로 보이고 걸어 다닌다.
- [ ] `Main`의 출력은 서버 창에만, `ClientMain`의 출력은 클라이언트 창마다 하나씩 찍힌다.
- [ ] (VS Code를 골랐다면) VS Code에서 고친 한 줄이 저장하자마자 Studio의 스크립트에 보이고, 반대 방향도 된다. VS Code에서 `game:GetService(`를 치면 서비스 이름이 자동 완성된다.
- [ ] (AI 도구를 이었다면) 그 도구에게 "Workspace에 무엇이 있는지 알려 줘"라고 하면 Studio에 있는 것을 답한다.
- [ ] Device Simulator에서 폰 화면으로 바꾸면 이동 스틱이 보인다.
- [ ] 폰의 Roblox 앱에서 같은 계정으로 이 비공개 게임에 들어갈 수 있다.
- [ ] Configure Place의 최대 인원이 8이다.
- [ ] 클라이언트 4개의 캐릭터가 모두 R15이고 키가 같다.
- [ ] Creator Dashboard에서 이 게임의 Audience 항목을 찾았고, Limited로 바꾸는 데 필요한 조건을 확인했다.

## 주의할 곳

- 편집 방식은 한 번 고르면 끝까지 간다. Script Sync를 쓰다가 Studio 편집기로 같은 스크립트를 함께 고치면 한쪽 변경이 덮인다.
- Script Sync는 속성이나 태그가 달린 스크립트를 제대로 다루지 못한다. 스크립트에는 속성과 태그를 달지 않는다. 상태는 폴더와 모형의 속성에 둔다.
- Script Sync가 맞추는 것은 Script, LocalScript, ModuleScript, Folder뿐이다. 원격 이벤트(`Remotes`), 맵(`Map`), 화면(`Hud`)은 Studio에만 있으므로 그 폴더들은 동기화하지 않는다. 동기화하는 세 폴더 안에는 스크립트와 폴더만 둔다.
- 혼자 만들므로 Team Test는 쓰지 않는다. 여러 사람이 필요한 확인은 `Server & Clients`로 하고, 진짜 사람이 필요한 확인은 테스트 단계에서 한다.
