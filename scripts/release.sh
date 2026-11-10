#!/bin/sh
# Publica uma versao da CAMADA df4p do OmniRoute: grava o VERSION, commita, marca
# a tag anotada da camada e empurra.
#
# A tag marca a NOSSA camada, nunca o app. O app e o upstream (3.8.x) e o
# namespace `v*` ja pertence a ele (centenas de tags, incluindo uma `v1.x`) — por
# isso a tag da camada e `camada-vX.Y.Z`: dois versionamentos convivendo sem se
# atropelar. O numero vive em VERSION (fonte unica do carimbo); a tag e o registro
# publico da mesma coisa.
#
#   sh scripts/release.sh 1.1.0     # grava VERSION, commita, marca e empurra
#   sh scripts/release.sh --show    # versao, ultima tag da camada, branch, sujeira
#
# O push vai para o remote `fork` (o nosso). A `origin` aponta para o UPSTREAM
# (diegosouzapw/OmniRoute) e nao se escreve nela. Em container com GH_TOKEN do
# ambiente, empurre com `env -u GH_TOKEN -u GITHUB_TOKEN -u GH_TOKEN_FBEE` para a
# credencial do remote valer (variavel de outra conta sombreia a do remote).
set -eu

VERSION_FILE="VERSION"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

TAG_PREFIX="camada-v"
PUSH_REMOTE="$(git remote 2>/dev/null | grep -x fork || echo origin)"

show() {
  echo "VERSION (arquivo): $(cat "${VERSION_FILE}" 2>/dev/null || echo '—')"
  echo "Ultima tag camada: $(git tag -l "${TAG_PREFIX}*" 2>/dev/null | sort -V | tail -n 1 || echo 'nenhuma')"
  echo "Ultimo commit:     $(git log -1 --format='%h %s' 2>/dev/null || echo '—')"
  echo "Branch:            $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '—')"
  echo "Remote de push:    ${PUSH_REMOTE}"
  echo "Arvore suja:       $(test -n "$(git -c core.fileMode=false status --porcelain)" && echo 'SIM (o carimbo nao vai representar o commit)' || echo 'nao')"
}

if [ "${1:-}" = "--show" ] || [ "$#" -eq 0 ]; then
  show
  exit 0
fi

NEW_VERSION="${1#v}"

case "${NEW_VERSION}" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "release: versao invalida '${1}' — use X.Y.Z (ex.: 1.1.0)" >&2; exit 1 ;;
esac

CURRENT="$(cat "${VERSION_FILE}" 2>/dev/null || echo '')"
if [ "${NEW_VERSION}" = "${CURRENT}" ]; then
  echo "release: ${NEW_VERSION} ja e a versao do arquivo — nada a gravar" >&2
  exit 1
fi

if [ -n "$(git -c core.fileMode=false status --porcelain)" ]; then
  echo "release: arvore suja. Commite (ou descarte) antes de marcar uma versao." >&2
  git status --short
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${TAG_PREFIX}${NEW_VERSION}" >/dev/null 2>&1; then
  echo "release: tag ${TAG_PREFIX}${NEW_VERSION} ja existe" >&2
  exit 1
fi

UPSTREAM_VERSION_VALUE="$(sh -c '. ./scripts/version-lib.sh; df4p_kv UPSTREAM_VERSION upstream_version' 2>/dev/null || true)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "release: camada ${CURRENT:-?} -> ${NEW_VERSION} em ${BRANCH} (upstream ${UPSTREAM_VERSION_VALUE:-?})"

printf '%s\n' "${NEW_VERSION}" > "${VERSION_FILE}"
git add "${VERSION_FILE}"
git commit -m "chore(versao): ${NEW_VERSION}"
git tag -a "${TAG_PREFIX}${NEW_VERSION}" -m "camada df4p do OmniRoute ${NEW_VERSION} (upstream ${UPSTREAM_VERSION_VALUE:-?})"

echo "release: tag ${TAG_PREFIX}${NEW_VERSION} criada. Empurrando commit e tag para ${PUSH_REMOTE}..."
git push "${PUSH_REMOTE}" "${BRANCH}"
git push "${PUSH_REMOTE}" "${TAG_PREFIX}${NEW_VERSION}"

show
echo "release: feito. A tag ${TAG_PREFIX}${NEW_VERSION} e o registro publico do que foi ao ar."
