#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -gt 1 ]; then
	echo "usage: $0 [output-json]" >&2
	exit 2
fi

: "${PANGOLIN_API_ENDPOINT:?set PANGOLIN_API_ENDPOINT to the API origin, without /v1}"
: "${PANGOLIN_API_KEY:?set PANGOLIN_API_KEY to a read-only organization API key}"
: "${PANGOLIN_ORG_ID:?set PANGOLIN_ORG_ID to the organization ID}"

output_file="${1:-topology/public.json}"
api_endpoint="${PANGOLIN_API_ENDPOINT%/}/v1"
temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "$temporary_root/shulker-pangolin-topology.XXXXXX")"

cleanup() {
	case "$temporary_dir" in
	"$temporary_root"/shulker-pangolin-topology.*)
		rm -rf -- "$temporary_dir"
		;;
	esac
}
trap cleanup EXIT

umask 077

api_get() {
	path="$1"
	destination="$2"
	curl \
		--fail-with-body \
		--silent \
		--show-error \
		--retry 3 \
		--retry-all-errors \
		--connect-timeout 10 \
		--max-time 60 \
		--header "Authorization: Bearer $PANGOLIN_API_KEY" \
		--header "Accept: application/json" \
		--output "$destination" \
		"$api_endpoint$path"

	jq -e '.success == true and .error == false' "$destination" >/dev/null
}

sites_file="$temporary_dir/sites.json"
resources_file="$temporary_dir/resources.json"
domains_file="$temporary_dir/domains.json"
targets_file="$temporary_dir/targets.jsonl"
sanitized_file="$temporary_dir/public.json"

api_get "/org/$PANGOLIN_ORG_ID/sites?pageSize=1000&page=1" "$sites_file"
api_get "/org/$PANGOLIN_ORG_ID/resources?pageSize=1000&page=1" "$resources_file"
api_get "/org/$PANGOLIN_ORG_ID/domains?limit=1000&offset=0" "$domains_file"

: >"$targets_file"
while IFS= read -r resource_id; do
	case "$resource_id" in
	'' | *[!0-9]*)
		echo "Pangolin returned an invalid resource ID" >&2
		exit 1
		;;
	esac

	resource_targets="$temporary_dir/targets-$resource_id.json"
	api_get "/resource/$resource_id/targets?limit=1000&offset=0" "$resource_targets"
	jq -cn \
		--arg resourceId "$resource_id" \
		--slurpfile response "$resource_targets" \
		'{
			resourceId: $resourceId,
			targets: ($response[0].data.targets // $response[0].data // [])
		}' >>"$targets_file"
done < <(jq -r '.data.resources // .data // [] | .[].resourceId' "$resources_file")

collected_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

jq -n \
	--arg collectedAt "$collected_at" \
	--slurpfile sitesResponse "$sites_file" \
	--slurpfile resourcesResponse "$resources_file" \
	--slurpfile domainsResponse "$domains_file" \
	--slurpfile targetResponses "$targets_file" '
	def sourceSites: ($sitesResponse[0].data.sites // $sitesResponse[0].data // []);
	def sourceResources: ($resourcesResponse[0].data.resources // $resourcesResponse[0].data // []);
	def sourceDomains: ($domainsResponse[0].data.domains // $domainsResponse[0].data // []);
	def siteId:
		(.niceId // .siteId // .id | tostring);
	def siteName:
		(.name // .niceId // .siteId // .id | tostring);
	def resourceTargets($resourceId):
		[
			$targetResponses[]
			| select(.resourceId == ($resourceId | tostring))
			| .targets[]
		];
	def publicSiteId($sourceId):
		first(
			sourceSites[]
			| select((.siteId // .id | tostring) == ($sourceId | tostring))
			| siteId
		) // ($sourceId | tostring);

	{
		schema: 1,
		pangolin: {
			collectedAt: $collectedAt,
			domains: [
				sourceDomains[]
				| {
					domain: (.baseDomain // .domain // ""),
					type: (.type // "unknown"),
					verified: (.verified // false)
				}
				| select(.domain != "")
			]
			| sort_by(.domain),
			resources: [
				sourceResources[]
				| . as $resource
				| {
					id: ($resource.niceId // $resource.resourceId | tostring),
					name: ($resource.name // $resource.niceId // $resource.resourceId | tostring),
					domain: ($resource.fullDomain // $resource.domain // ""),
					protocol: (
						if ($resource.http // false) then
							if ($resource.ssl // true) then "https" else "http" end
						else
							($resource.protocol // $resource.mode // "unknown")
						end
					),
					enabled: ($resource.enabled // true),
					sites: (
						resourceTargets($resource.resourceId)
						| map(publicSiteId(.siteId))
						| unique
					)
				}
				| select(.domain != "")
			]
			| sort_by(.domain),
			sites: [
				sourceSites[]
				| {
					id: siteId,
					name: siteName,
					type: (.type // "unknown"),
					online: (.online // false)
				}
			]
			| sort_by(.name)
		}
	}' >"$sanitized_file"

jq -e '
	.schema == 1
	and (.pangolin.sites | type == "array")
	and (.pangolin.resources | type == "array")
	and (.pangolin.domains | type == "array")
	and all(.pangolin.resources[]; has("sites") and (.sites | type == "array"))
' "$sanitized_file" >/dev/null

mkdir -p -- "$(dirname "$output_file")"
mv -- "$sanitized_file" "$output_file"
echo "wrote sanitized Pangolin topology to $output_file"
