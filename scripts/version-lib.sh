#!/bin/sh
# Implementacao UNICA do rotulo de versao da camada df4p do OmniRoute.
#
# Este arquivo e sourced por scripts/build.sh e scripts/check-versioning.sh para
# que exista uma so definicao de rotulo no repo. Nenhum numero de versao vive
# aqui: a versao da camada vem do arquivo VERSION; a do app, do UPSTREAM_VERSION.
#
#   df4p_label <VERSION> <COMMIT> <MODIFIED>
#     VERSION   X.Y.Z (lido do VERSION)
#     COMMIT    short sha (>=7) ou `unknown` quando nao ha git
#     MODIFIED  true|false (ha mudanca de CONTEUDO na arvore)
#
# Imprime:
#   vX.Y.Z+<commit>   -> arvore limpa com git
#   vX.Y.Z+<commit>*  -> arvore com mudanca de conteudo
#   vX.Y.Z            -> sem git (commit `unknown`; nada de sha chutado)
df4p_label() {
  _v=$1
  _c=$2
  _m=$3
  if [ -z "${_c}" ] || [ "${_c}" = "unknown" ]; then
    printf 'v%s' "${_v}"
    return 0
  fi
  if [ "${_m}" = "true" ]; then
    printf 'v%s+%s*' "${_v}" "${_c}"
  else
    printf 'v%s+%s' "${_v}" "${_c}"
  fi
}

# df4p_kv <arquivo> <chave> -> imprime o valor de uma linha `chave=valor`
# (vazio quando o arquivo ou a chave nao existem).
df4p_kv() {
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2=[[:space:]]*//p" "$1" | head -n 1 | tr -d ' \t\r'
}
