#!/bin/sh
# Travas do padrao de versionamento da camada df4p do OmniRoute.
# Rode antes do PR: falham cedo, antes de qualquer release.
#
# A trava PRINCIPAL e a #2: a versao do upstream registrada em UPSTREAM_VERSION
# tem que casar com o `version` do package.json — a camada nao pode carimbar um
# upstream diferente do que ela de fato embala.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${ROOT}"
. "${ROOT}/scripts/version-lib.sh"

falhas=0
ok()   { echo "  ok   $*"; }
fail() { echo "  FALHA $*" >&2; falhas=$((falhas + 1)); }

echo "check-versioning: $(pwd)"

# 1. A versao da NOSSA camada tem uma fonte so: o arquivo VERSION, semantico e
#    rastreado pelo git.
VERSION_VALUE=""
if [ -s VERSION ] && grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION; then
  VERSION_VALUE="$(tr -d ' \n' < VERSION)"
  ok "VERSION = ${VERSION_VALUE}"
else
  fail "VERSION ausente ou fora do formato X.Y.Z"
fi
if git ls-files --error-unmatch VERSION >/dev/null 2>&1; then
  ok "VERSION rastreado pelo git"
else
  fail "VERSION NAO esta rastreado (a fonte da versao tem que estar no git)"
fi

# 2. UPSTREAM_VERSION: a versao do app de TERCEIROS que embalamos.
UPSTREAM_VERSION_VALUE=""
UPSTREAM_COMMIT_VALUE=""
if [ -s UPSTREAM_VERSION ]; then
  UPSTREAM_VERSION_VALUE="$(df4p_kv UPSTREAM_VERSION upstream_version)"
  UPSTREAM_COMMIT_VALUE="$(df4p_kv UPSTREAM_VERSION upstream_commit)"
fi
if git ls-files --error-unmatch UPSTREAM_VERSION >/dev/null 2>&1; then
  ok "UPSTREAM_VERSION rastreado pelo git"
else
  fail "UPSTREAM_VERSION NAO esta rastreado"
fi
if printf '%s' "${UPSTREAM_VERSION_VALUE}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "UPSTREAM_VERSION.upstream_version = ${UPSTREAM_VERSION_VALUE}"
else
  fail "UPSTREAM_VERSION sem 'upstream_version=' semantico (X.Y.Z)"
fi
if printf '%s' "${UPSTREAM_COMMIT_VALUE}" | grep -Eq '^[0-9a-f]{7,40}$'; then
  ok "UPSTREAM_VERSION.upstream_commit = ${UPSTREAM_COMMIT_VALUE}"
else
  fail "UPSTREAM_VERSION sem 'upstream_commit=' (sha de 7..40 hex)"
fi

# TRAVA PRINCIPAL: divergir do package.json significa que a camada diz carregar
# uma versao do upstream mas embala outra.
PKG_VERSION="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)"
if [ -z "${PKG_VERSION}" ]; then
  fail "nao consegui ler o 'version' do package.json"
elif [ -n "${UPSTREAM_VERSION_VALUE}" ] && [ "${PKG_VERSION}" = "${UPSTREAM_VERSION_VALUE}" ]; then
  ok "UPSTREAM_VERSION casa com package.json (${PKG_VERSION})"
else
  fail "UPSTREAM_VERSION (${UPSTREAM_VERSION_VALUE:-?}) != package.json (${PKG_VERSION})"
fi

# 3. O rotulo: provado nos tres casos (limpo / sujo / sem git).
TL="9.9.9"
case "$(df4p_label "${TL}" abc1234 false)" in
  "v${TL}+abc1234") ok "rotulo limpo: v${TL}+abc1234" ;;
  *) fail "rotulo fora do formato vX.Y.Z+<commit>" ;;
esac
case "$(df4p_label "${TL}" abc1234 true)" in
  "v${TL}+abc1234*") ok "arvore suja ganha '*': v${TL}+abc1234*" ;;
  *) fail "arvore suja nao marcou o rotulo com '*'" ;;
esac
case "$(df4p_label "${TL}" unknown false)" in
  "v${TL}") ok "sem git: rotulo sem sufixo de commit" ;;
  *) fail "sem git o rotulo deveria perder o sufixo" ;;
esac

# 3b. O rotulo REAL bate com a arvore REAL (sujo <-> '*'), e prova o conjunto
#     VERSION + sujeira calculada pelo proprio script.
if [ -n "${VERSION_VALUE}" ]; then
  LIVE_DISPLAY="$(sh scripts/build.sh --show 2>/dev/null | sed -n 's/^display:[[:space:]]*//p')"
  DIRTY=false
  if [ -n "$(git -c core.fileMode=false status --porcelain 2>/dev/null)" ]; then
    DIRTY=true
  fi
  case "${LIVE_DISPLAY}" in
    *\*) LIVE_DIRTY=true ;;
    *)   LIVE_DIRTY=false ;;
  esac
  if [ "${LIVE_DIRTY}" = "${DIRTY}" ]; then
    ok "rotulo real bate com a arvore (${LIVE_DISPLAY}; suja=${DIRTY})"
  else
    fail "rotulo real (${LIVE_DISPLAY}) nao bate com a arvore (suja=${DIRTY})"
  fi
fi

# 4. Nenhuma versao escrita a mao no codigo/UI. A versao do app so pode viver nos
#    manifestos (package.json / package-lock.json, que sao o que o runtime le) e
#    na documentacao: literal citado em codigo/UI reprova.
if [ -n "${UPSTREAM_VERSION_VALUE}" ]; then
  HARD="$(git grep -nE "\"${UPSTREAM_VERSION_VALUE}\"|'${UPSTREAM_VERSION_VALUE}'" -- src open-sse bin electron public scripts ':!*.json' ':!*.md' 2>/dev/null || true)"
  if [ -n "${HARD}" ]; then
    fail "versao do app (${UPSTREAM_VERSION_VALUE}) escrita a mao no codigo: $(printf '%s' "${HARD}" | head -n 3 | tr '\n' ' ')"
  else
    ok "versao do app nao escrita a mao no codigo/UI (so nos manifestos)"
  fi
fi
# A versao da NOSSA camada tambem nao pode estar escrita a mao: quem a escreve e
# o VERSION, lido pelos scripts do kit.
if [ -n "${VERSION_VALUE}" ]; then
  HARD_LAYER="$(git grep -nE "(^|[^0-9.])${VERSION_VALUE}([^0-9.]|$)" -- scripts/build.sh scripts/check-versioning.sh scripts/release.sh scripts/version-lib.sh 2>/dev/null || true)"
  if [ -n "${HARD_LAYER}" ]; then
    fail "versao da camada (${VERSION_VALUE}) escrita a mao no kit: $(printf '%s' "${HARD_LAYER}" | head -n 3 | tr '\n' ' ')"
  else
    ok "versao da camada nao escrita a mao (fonte unica: VERSION)"
  fi
fi

# 5. .dockerignore: nao pode excluir `.git` (sem ele o commit do carimbo sairia
#    `unknown`) nem os arquivos rastreados que o carimbo le. Os demais prunes de
#    contexto (tests, docs/i18n, .github ...) sao escolha do UPSTREAM para o
#    tamanho da imagem e nao entram no carimbo — a trava cobre o que o carimbo le.
if [ -f .dockerignore ]; then
  if grep -Eq '^[[:space:]]*(\*\*/)?\.git/?[[:space:]]*$' .dockerignore; then
    fail ".dockerignore exclui .git — o commit do carimbo sairia 'unknown'"
  else
    ok ".git entra no contexto de build"
  fi
  KIT_FILES="VERSION UPSTREAM_VERSION package.json package-lock.json scripts/version-lib.sh scripts/build.sh scripts/check-versioning.sh scripts/release.sh"
  EXCL="$(git ls-files -ci --exclude-from=.dockerignore -- ${KIT_FILES} 2>/dev/null || true)"
  if [ -n "${EXCL}" ]; then
    fail ".dockerignore exclui arquivo rastreado que o carimbo le: $(printf '%s' "${EXCL}" | tr '\n' ' ')"
  else
    ok ".dockerignore nao exclui os arquivos rastreados que o carimbo le"
  fi
else
  ok "sem .dockerignore"
fi

# 6. O carimbo e gerado, nunca versionado.
if git ls-files --error-unmatch .build-info.json >/dev/null 2>&1; then
  fail ".build-info.json esta RASTREADO (carimbo e gerado, nunca versionado)"
else
  ok ".build-info.json nao versionado"
fi
if grep -Eq '^[[:space:]]*/?\.build-info\.json[[:space:]]*$' .gitignore 2>/dev/null; then
  ok ".build-info.json ignorado pelo git"
else
  fail ".build-info.json ausente do .gitignore (carimbo e gerado)"
fi

# 7. Se ja existe tag da CAMADA, o VERSION nao pode ficar atras dela. O namespace
#    `v*` pertence ao upstream (centenas de tags, incluindo uma `v1.x`); a camada
#    usa `camada-vX.Y.Z` exatamente para nao atropelar nem ser atropelada.
ultima_tag="$(git tag -l 'camada-v*' 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -n "${ultima_tag}" ]; then
  atras="$(printf '%s\n%s\n' "${ultima_tag#camada-v}" "${VERSION_VALUE}" | sort -V | head -n 1)"
  if [ "${atras}" = "${VERSION_VALUE}" ] && [ "${ultima_tag#camada-v}" != "${VERSION_VALUE}" ]; then
    fail "VERSION (${VERSION_VALUE}) esta atras da ultima tag da camada (${ultima_tag})"
  else
    ok "VERSION em dia com a ultima tag da camada (${ultima_tag})"
  fi
else
  ok "nenhuma tag camada-v* ainda (a primeira release sera a referencia)"
fi
if [ -n "${VERSION_VALUE}" ] && git rev-parse -q --verify "refs/tags/v${VERSION_VALUE}" >/dev/null 2>&1; then
  ok "v${VERSION_VALUE} ja pertence ao upstream — por isso a camada marca camada-v${VERSION_VALUE}"
fi

if [ "${falhas}" -ne 0 ]; then
  echo "check-versioning: ${falhas} falha(s)" >&2
  exit 1
fi
echo "check-versioning: tudo verde"
