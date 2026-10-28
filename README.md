# 배 가라앉히지 마 (Don't Sink the Boat!)

Roblox 파티 게임. 기획은 `docs/`, 코드는 `src/`에 있다.

## 폴더

```
docs/   개발 계획서 (README.md부터 읽는다)
src/
  Shared/   → Studio의 ReplicatedStorage/Shared
  Server/   → Studio의 ServerScriptService/Server
  Client/   → Studio의 StarterPlayer/StarterPlayerScripts/Client
```

`src/`의 파일은 모두 자리만 있는 상태다. `Main.server.luau`는 `server up`, `ClientMain.local.luau`는 `client up`을 찍는다.

## 시작하기

`docs/S01-project-setup.md`를 위에서부터 한다. 이 저장소는 그중 스크립트 쪽 폴더 틀(3번)과 Git 준비(4번의 5·6)를 이미 해 둔 것이다.

남은 것은 Studio와 VS Code에서 하는 일이다. 4번 안쪽의 1(Script Sync 켜기), 2(위 표의 세 폴더를 각각 우클릭해 `Script Sync ⟩ Sync to`로 이 저장소의 `src/` 아래 폴더에 맞추기), 4(Luau 확장과 Companion 플러그인 설치)다. `Remotes`, `Participants`, `Map`, `Hud`, `Assets`는 Studio에만 있어서 Studio에서 만든다.
