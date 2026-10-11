#!/bin/sh
# Build snapshots off to the side; publish only a complete successful site.
set -eu
umask 077

while true; do
	fingerprint=$(
		{
			printf '%s\n' "$QUARTZ_IMAGE"
			sha256sum /run/quartz-agents.json /run/quartz-publish.sh /run/quartz-index.mjs /usr/src/app/quartz.config.ts
			find /notes -type f -print0 | sort -z | xargs -0 -r sha256sum
		} | sha256sum | cut -d ' ' -f 1
	)
	if [ ! -f /output/current/index.html ] || [ "$fingerprint" != "$(cat /output/fingerprint 2>/dev/null || true)" ]; then
		stage=$(mktemp -d /output/.build.XXXXXX)
		mkdir "$stage/content"
		if (
			cp -R /notes/. "$stage/content/" || exit 1
			# Notes may link elsewhere on the host; never follow or publish those links.
			find "$stage/content" -type l -delete || exit 1
			node /run/quartz-index.mjs "$stage/content" || exit 1
			node quartz/bootstrap-cli.mjs build -d "$stage/content" -o "$stage/public" --concurrency 2 || exit 1
			test -f "$stage/public/index.html"
		); then
			previous=$(readlink /output/current 2>/dev/null || true)
			rm -f /output/.current-next
			ln -s "$(basename "$stage")/public" /output/.current-next
			mv -Tf /output/.current-next /output/current
			printf '%s\n' "$fingerprint" >/output/fingerprint
			# Retain only the new snapshot; generated files can always be rebuilt.
			case "$previous" in
			.build.*/public) rm -rf -- "/output/${previous%/public}" ;;
			esac
			printf 'Quartz site published.\n'
		else
			rm -rf -- "$stage"
			printf 'Quartz build failed; previous site retained.\n' >&2
		fi
	fi
	sleep "${UPDATE_INTERVAL:-60}"
done
