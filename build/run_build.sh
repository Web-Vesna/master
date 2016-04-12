#!/bin/bash

rm -f /home/p.berezhnoy/rpmbuild/RPMS/noarch/*

cd "$( dirname "${BASH_SOURCE[0]}" )"

git log -1 > __last_commit
rpmbuild -ba apek-energo.spec
rm -f __last_commit
