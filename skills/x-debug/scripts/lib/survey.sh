# shellcheck shell=bash
# Project survey modules. xdh sources this public entry point; the implementation
# is split by responsibility so cache freshness and graph routing stay testable.
# shellcheck source=lib/survey-cache.sh
. "$XDH_LIB/survey-cache.sh"
# shellcheck source=lib/survey-render.sh
. "$XDH_LIB/survey-render.sh"
# shellcheck source=lib/survey-graph.sh
. "$XDH_LIB/survey-graph.sh"
# shellcheck source=lib/survey-command.sh
. "$XDH_LIB/survey-command.sh"
