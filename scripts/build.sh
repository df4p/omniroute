#!/bin/sh
# Build unico da camada df4p do OmniRoute — todo carimbo e todo build passa aqui.
#
# O OmniRoute e codigo de TERCEIROS (upstream `cheaper-inference/OmniRoute`, antigo
# `diegosouzapw/OmniRoute`). Por isso convivem DUAS versoes, sem brigar:
#   VERSION          -> a NOSSA camada (o fork df4p) — e ela que ganha rotulo e tag.
#   UPSTREAM_VERSION -> o app de terceiros (semver + commit da base que carregamos).
#
# Este script:
#   1. calcula o rotulo `vX.Y.Z+<commit>` (`*` quando ha mudanca de CONTEUDO) com
#      `git -c core.fileMode=false status --porcelain` — quem calcula o rotulo
#      calcula a sujeira, nunca delega o palpite a ferramenta de terceiro;
#   2. grava o carimbo `.build-info.json` (GERADO, nunca versionado) com o nosso
#      rotulo + o upstream (versao + commit) + a imagem que a stack sobe;
#   3. roda o build do projeto (`package.json` -> `npm run build`) SOMENTE se a
#      toolchain e as dependencias existirem; quando nao roda, diz em voz alta o
#      que pulou (nada de verde falso).
#
#   sh scripts/build.sh          # carimba + roda o build do projeto (se der)
#   sh scripts/build.sh --show   # retrato atual: nao carimba e nao constroi
#
# DF4P_REQUIRE_APP_BUILD=1 torna o build do projeto obrigatorio (falha se pular).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${ROOT}"
. "${ROOT}/scripts/version-lib.sh"

VERSION_FILE="VERSION"
UPSTREAM_FILE="UPSTREAM_VERSION"

if [ ! -s "${VERSION_FILE}" ]; then
  echo "build: ${VERSION_FILE} ausente ou vazio" >&2
  exit 1
fi
VERSION_VALUE="$(tr -d ' \t\r\n' < "${VERSION_FILE}")"

if [ ! -s "${UPSTREAM_FILE}" ]; then
  echo "build: ${UPSTREAM_FILE} ausente — a camada precisa registrar o upstream que carrega" >&2
  exit 1
fi
UPSTREAM_VERSION_VALUE="$(df4p_kv "${UPSTREAM_FILE}" upstream_version)"
UPSTREAM_COMMIT_VALUE="$(df4p_kv "${UPSTREAM_FILE}" upstream_commit)"
if [ -z "${UPSTREAM_VERSION_VALUE}" ]; then
  echo "build: ${UPSTREAM_FILE} sem a chave 'upstream_version='" >&2
  exit 1
fi

COMMIT_VALUE="$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
BUILD_TIME_VALUE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Sujeira de CONTEUDO: mudanca so de permissao (comum em sincronizacao entre
# maquinas/mounts) nao conta — nao muda uma linha do que foi publicado e so
# serviria para pintar um `*` falso no rotulo.
MODIFIED_VALUE=false
if [ "${COMMIT_VALUE}" != "unknown" ]; then
  if [ -n "$(git -c core.fileMode=false status --porcelain 2>/dev/null)" ]; then
    MODIFIED_VALUE=true
  fi
fi

DISPLAY="$(df4p_label "${VERSION_VALUE}" "${COMMIT_VALUE}" "${MODIFIED_VALUE}")"

# Imagem que a stack `docker-omniroute` sobe: o app upstream na versao carregada.
# Sobrescreva com DF4P_OMNIROUTE_IMAGE se a stack apontar para outra referencia.
OMNIROUTE_IMAGE="${DF4P_OMNIROUTE_IMAGE:-diegosouzapw/omniroute:${UPSTREAM_VERSION_VALUE}}"

if [ "${1:-}" = "--show" ]; then
  echo "version:          ${VERSION_VALUE}"
  echo "upstream_version: ${UPSTREAM_VERSION_VALUE}"
  echo "upstream_commit:  ${UPSTREAM_COMMIT_VALUE}"
  echo "commit:           ${COMMIT_VALUE}"
  echo "modified:         ${MODIFIED_VALUE}"
  echo "display:          ${DISPLAY}"
  echo "image:            ${OMNIROUTE_IMAGE}"
  exit 0
fi

# Carimbo gerado — NUNCA versionado (a trava reprova se aparecer rastreado).
write_stamp() {
  cat > .build-info.json <<EOF
{
  "service": "omniroute-camada-df4p",
  "layer": "df4p",
  "version": "${VERSION_VALUE}",
  "tag": "camada-v${VERSION_VALUE}",
  "commit": "${COMMIT_VALUE}",
  "build_time": "${BUILD_TIME_VALUE}",
  "modified": ${MODIFIED_VALUE},
  "display": "${DISPLAY}",
  "upstream_version": "${UPSTREAM_VERSION_VALUE}",
  "upstream_commit": "${UPSTREAM_COMMIT_VALUE}",
  "app_build": "$1",
  "images": {
    "omniroute": "${OMNIROUTE_IMAGE}"
  },
  "stack": "docker-omniroute",
  "tags_url": "https://github.com/df4p/omniroute/tags"
}
EOF
}

# --- build do projeto (Next.js) ---------------------------------------------
# So roda com toolchain + dependencias presentes. Sem node_modules o `npm run
# build` nem chega ao compilador; declarar sucesso aqui seria verde falso.
SKIP_REASON=""
if ! command -v npm >/dev/null 2>&1; then
  SKIP_REASON="npm ausente no PATH"
elif [ ! -f package-lock.json ]; then
  SKIP_REASON="package-lock.json ausente (build nao reproduzivel)"
elif [ ! -d node_modules ]; then
  SKIP_REASON="node_modules ausente (rode 'npm ci' antes)"
fi

if [ -z "${SKIP_REASON}" ]; then
  write_stamp "pending"
  echo "build: rodando o build do projeto (npm run build)..."
  if npm run build; then
    write_stamp "ran"
    APP_BUILD="ran"
    echo "build: build do projeto OK"
  else
    write_stamp "failed"
    echo "build: build do projeto FALHOU (o carimbo registra app_build=failed)" >&2
    exit 1
  fi
else
  write_stamp "skipped"
  APP_BUILD="skipped"
  echo "build: AVISO — build do projeto PULADO: ${SKIP_REASON}" >&2
  echo "build: AVISO — o carimbo foi escrito, mas a aplicacao NAO foi construida neste ambiente." >&2
  if [ "${DF4P_REQUIRE_APP_BUILD:-0}" = "1" ]; then
    echo "build: DF4P_REQUIRE_APP_BUILD=1 e o build do projeto nao rodou — falhando." >&2
    exit 1
  fi
fi

echo "build: camada=${VERSION_VALUE} upstream=${UPSTREAM_VERSION_VALUE} commit=${COMMIT_VALUE} modified=${MODIFIED_VALUE}"
echo "build: carimbo escrito em .build-info.json (gerado, nunca versionado)"
echo "build: pronto — ${DISPLAY} (app_build=${APP_BUILD})"
