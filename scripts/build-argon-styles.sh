#!/bin/sh
set -eu

cd "$1"
if [ -f tools/build-theme-assets.sh ]; then
    # Argon 3.2 builds separate stylesheets and fingerprints the files it ships.
    set -- sh tools/build-theme-assets.sh
else
    # Argon 3.1 ships a single compiled stylesheet.
    set -- lessc less/cascade.less htdocs/luci-static/argon/css/cascade.css
fi

# Match the compiler used by Argon's own stylesheet checks.
exec npm exec --yes --package=less@4.1.3 -- "$@"
