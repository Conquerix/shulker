#!/usr/bin/env bash
# Inherit group write for future Git worktrees/files even when a tool uses umask 0077.
set -euo pipefail
project=$1
group=$2
[ -d "$project" ] && [ ! -L "$project" ]
# Stay inside this project; never follow a link into private provider/host state.
find "$project" -xdev \( -type d -o -type f \) -exec setfacl -m "g:$group:rwX,m::rwX" -- {} +
find "$project" -xdev -type d -exec setfacl -m "d:u::rwx,d:g::rwx,d:g:$group:rwx,d:m::rwx,d:o::---" -- {} +
