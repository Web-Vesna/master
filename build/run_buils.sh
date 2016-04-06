#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LAST_COMMIT=`git log -1 | tr '\n' '\\n'`
rpmbuild --define "__latest_commit $(LAST_COMMIT)" -ba $(DIR)/apek-energo.spec
