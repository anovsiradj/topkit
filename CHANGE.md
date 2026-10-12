
20191210143402
git submodule add git@github.com:danielebailo/couchdb-dump.git couchdb/dump
git submodule update --init

20191210143402
./xvfb-simple.sh

20200110184259
./linux/cleanup1.sh

?
./devices/laptop-keyboard-toggle.sh
./version-release-checker/php

20210128175431
./network/wgetping.sh

20260129
fs/duplicate
programs/gallery

20261012
restructure: programs/ -> apps/gallery/ (index.php, api.php, web.php, css/, js/)
restructure: root scripts -> kits/ (file-hasher, text-html-print, version-release-checker, duplicate-finder, password-bcrypt, flat-array, wgetping)
restructure: git/editor/db scripts -> dev/ (git-repo-lite, git-default, editor-create-project.py, mysql-user-reset, psql-*)
restructure: linux scripts -> tux/ (xvfb-simple, wine-vacuum-cleaner, cleanup1)
restructure: windows scripts -> win/ (PHPServer.ps1, merge-*.bat, editor-create-project.ps1, pwsh-notes)
restructure: php/arguments.php -> libs/php/arguments.php
cleanup: keyboard/ (empty), devices/touchpad-toggle.sh.tmp

