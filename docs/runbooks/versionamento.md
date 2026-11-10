# Versionamento da camada df4p sobre o OmniRoute

Este repositório é um **fork de código de terceiros**. O upstream é
`cheaper-inference/OmniRoute` (o antigo `diegosouzapw/OmniRoute` é o mesmo repo
renomeado; o GitHub redireciona) e o nosso fork é `df4p/omniroute`. Por isso não
existe **uma** versão do "OmniRoute inteiro": existem duas, convivendo sem brigar.

- **O app é do upstream.** A versão `3.8.x` é dele, evolui no ritmo dele e **não é
  a nossa** — nós não a tagueamos.
- **A nossa camada é a do fork.** É ela que ganha `VERSION`, rótulo, carimbo e
  tag. A camada embala o app, então ela **registra** qual upstream carrega.

Regra de ouro: **um número por coisa.** Versionar a nossa camada com o número do
upstream (ou vice-versa) faz quem opera ler "3.8.52" e não saber se aquilo é o app
ou o nosso fork.

## Onde cada versão vive

| Onde | O que é |
| --- | --- |
| `VERSION` | **Fonte única da NOSSA camada.** Semântico, sem `v` (hoje `1.0.0`). |
| `UPSTREAM_VERSION` | O app de terceiros que embalamos: `upstream_version` (semver) **e** `upstream_commit` (sha da base). |
| rótulo | `vX.Y.Z+<commit>`; sufixo `*` quando há mudança de **conteúdo** na árvore. Sem git: `vX.Y.Z` (commit `unknown` — nada de sha chutado). |
| `.build-info.json` | Carimbo escrito por `scripts/build.sh` (gerado, **nunca versionado**), com o nosso rótulo + o upstream + a imagem que a stack sobe. |
| tag da camada | `camada-vX.Y.Z` — **registro público** no repositório; marca o commit da camada que foi para o ar. |

Nenhum número de versão é escrito à mão: quem escreve é `scripts/build.sh`, a
partir do `VERSION`, usando a implementação única em `scripts/version-lib.sh`.

### Por que a tag da camada é `camada-vX.Y.Z` e não `vX.Y.Z`

O fork herda **todas** as tags do upstream — são centenas, de `v0.1.0` a `v3.8.52`,
incluindo a nossa `1.0.0` (o upstream já tem uma `v1.0.0`). O namespace `vX.Y.Z`
pertence ao app; se a camada marcasse `v1.0.0` ela colidiria com a tag histórica do
upstream e a primeira release da camada seria impossível. Então a camada marca
`camada-vX.Y.Z`: dois versionamentos no mesmo repositório, cada um com o seu
namespace. `scripts/check-versioning.sh` confere que o `VERSION` não ficou atrás da
última tag `camada-v*` e aponta quando o `vX.Y.Z` "nu" já é do upstream.

### A trava que impede a camada de mentir

O `UPSTREAM_VERSION` tem que **casar com o `version` do `package.json`**. É o
upstream que manda no `package.json` (nós não o editamos); se a camada registra
`3.8.52` mas o `package.json` diz outra coisa, o carimbo está descrevendo um app
que ela não embala. `scripts/check-versioning.sh` reprova essa divergência, e é a
primeira coisa a olhar quando o padrão fica vermelho.

## Comandos

```sh
sh scripts/build.sh --show      # retrato: camada, upstream, commit, sujeira, rótulo, imagem
sh scripts/build.sh             # carimba .build-info.json + roda o build do projeto (se der)
sh scripts/check-versioning.sh  # travas do padrão (rode antes do PR)
sh scripts/release.sh 1.1.0     # grava VERSION, commita, cria a tag anotada e empurra
sh scripts/release.sh --show    # versão, última tag da camada, branch e sujeira
```

O `scripts/build.sh` monta o carimbo assim:

1. lê `VERSION` (nossa camada) e `UPSTREAM_VERSION` (app + commit da base);
2. calcula a sujeira **ele mesmo**, com `git -c core.fileMode=false status
   --porcelain` — quem calcula o rótulo calcula a sujeira, nunca confia no palpite
   de ferramenta de terceiro (worktree, `.git` fora do contexto e git ausente
   mudam esse palpite em silêncio);
3. grava `.build-info.json` com `display`, `upstream_version`, `upstream_commit` e
   a imagem que a stack `docker-omniroute` sobe;
4. roda o build do projeto (`npm run build`) **somente** se a toolchain e as
   dependências existirem. Sem `node_modules` ele **não** roda e diz isso em voz
   alta, gravando `app_build: "skipped"` no carimbo — nada de verde falso. Use
   `DF4P_REQUIRE_APP_BUILD=1` para exigir o build do app e falhar quando ele não
   puder rodar.

## Regra de release

1. Merge do PR na branch de release do fork (branch tipada + PR; nunca commit
   direto no tronco).
2. `sh scripts/release.sh X.Y.Z` — a tag `camada-vX.Y.Z` marca o commit da camada
   publicado; o script recusa repetir a versão atual, árvore suja e tag já
   existente.
3. Toda entrega que muda a camada sobe com versão nova: correção ⇒ patch,
   funcionalidade ⇒ minor, mudança incompatível ⇒ major.
4. Depois do deploy: `sh scripts/build.sh --show` no commit publicado deve devolver
   o mesmo `display` (commit esperado, `modified: false`).

### Quando o upstream sobe de versão

O upstream publica a nova linha (por exemplo `release/v3.8.54`) e o `package.json`
dele passa a dizer a nova versão **no commit do próprio upstream** — a gente não
edita esse arquivo. O que a nossa camada faz:

1. sincroniza o fork com a nova linha do upstream (a `package.json` nova vem
   junto, com o commit dela);
2. atualiza `UPSTREAM_VERSION` (`upstream_version` = nova semver, `upstream_commit`
   = sha da base que passamos a carregar);
3. roda `sh scripts/check-versioning.sh` — verde significa que o `UPSTREAM_VERSION`
   casa com o `package.json` que veio;
4. se a **nossa** camada mudou (patches do fork, ajustes de script), sobe o
   `VERSION` dela e marca `camada-vX.Y.Z`; se foi só troca de upstream, o
   `VERSION` da camada pode continuar e o carimbo novo já registra o upstream novo.

## Armadilhas

- **Duas versões, um número cada.** O app é `3.8.x` do upstream; a camada é nossa
  (`1.0.0`). Não tagueie `vX.Y.Z` (namespace do upstream) nem escreva a versão do
  app à mão no código/UI — o runtime lê o `package.json`; quem carimba é o
  `scripts/build.sh`.
- **Mudança só de permissão não é sujeira.** O carimbo usa
  `git -c core.fileMode=false status`, senão a sincronização entre máquinas/mounts
  pintaria `*` numa árvore limpa (neste mount os bits de permissão aparecem como
  sujeira falsa).
- **`.dockerignore` não exclui `.git` nem o que o carimbo lê.** Excluir `.git`
  deixa o commit do carimbo em `unknown`. O upstream poda do contexto de build o
  que não vai para a imagem (`tests`, `docs/i18n/**`, `.github`, `electron`…); esse
  prune é escolha dele e não entra no carimbo — a trava cobre `.git`, `VERSION`,
  `UPSTREAM_VERSION`, `package.json`, `package-lock.json` e os scripts do kit. O
  preço de manter `.git` no contexto é o tamanho do histórico (~4 GB); é o custo
  aceito para o commit do carimbo nunca sair `unknown`.
- **O carimbo não se versiona.** `.build-info.json` é gerado; se aparecer
  rastreado, a trava reprova.
- **A imagem oficial é a do upstream.** A stack `docker-omniroute` sobe
  `diegosouzapw/omniroute:<upstream_version>` (imagem pronta), então o que este
  repositório produz é o carimbo e a tag da camada — não há imagem nossa para
  carimbar aqui, e o `Dockerfile` do upstream não é alterado por esta camada.
