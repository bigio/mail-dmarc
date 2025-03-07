#!/bin/sh

. .release/base.sh || exit

assure_repo_is_clean || exit

pod2markdown --perldoc-url-prefix=sco lib/Mail/DMARC.pm > README.md

if ! repo_is_clean; then
    git add README.md
    git commit -m "doc(README): updated"
fi
