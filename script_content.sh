#!/bin/bash

echo 'PART 1: Get DocFx build indexes to get lists of all pages on a site, viewed or not'

storageAccountName="" #Azure Storage account name
accountKey="" #Azure Storage account key
containerName="" #Azure Storage container name
sourceFile="index.json"
siteUrl="" #Example: docs.mysite.com
azureExport="content"
export=$azureExport.csv

echo "Removing localIndexes directory from previous run if exists, creating new one"
if [[ -d localIndexes ]]; then
    rm -rf localIndexes
fi

mkdir localIndexes

jq -r '.[] | "\(.blobDirName)|\(.blobDirPath)"' key_dirs.json |
    while IFS="|" read -r blobDirName blobDirPath; do

for dir in $blobDirName ; do

blobName=`echo $blobDirName | tr -d '\r'`
blobPath=`echo $blobDirPath | tr -d '\r'`

echo 'Download index.json (a list of all pages that exist) from each subsite'
az storage blob download --container-name $containerName --file localIndexes/$blobName.json --name $blobPath/$sourceFile --account-key $accountKey --account-name $storageAccountName

echo "Rearrange the structure of index.json so it's easier to process"
# `fullUrl` is `index only` because the column needs to match a column in the Azure Application Insights log files extract
jq --arg blobDirName $blobDirName '.[] | { fullUrl: "index only", href: .href, name: .title, subsite: $blobDirName}' localIndexes/$blobDirName.json > temp.tmp && mv temp.tmp localIndexes/$blobDirName.json

done
done

echo 'Combine the JSON file that is a list of all pages from each subsite into a single JSON file'
jq -s . localIndexes/*.json > localIndexes/docfx.json

echo 'Remove ` | Articles` in name'
jq '.[].name |= (gsub(" \\| Articles"; ""))' localIndexes/docfx.json > temp.tmp && mv temp.tmp localIndexes/docfx.json
jq '.[].name |= (gsub("\\| Articles"; ""))' localIndexes/docfx.json > temp.tmp && mv temp.tmp localIndexes/docfx.json

echo "PART 2: Process the logs exported from Azure Application Insights"

echo 'Prepare Azure export for transformation to JSON'
echo "Starting work on the $azureExport export"
echo 'Remove final output file if exists'
if [[ -f final-$azureExport.csv ]]; then
    rm final-$azureExport.csv
fi

echo "Removing troubleshoot/$azureExport directory from previous run if exists, creating new one"
if [[ -d troubleshoot/$azureExport ]]; then
    rm -rf troubleshoot/$azureExport
fi

mkdir troubleshoot/$azureExport

echo 'Removing characters from pages accessed via search results (the characters `?=`) and anchors (the `#` character) so they count as a view of the page they point to'
sed -E -e 's|\?[^,]*,|",|' -e 's|\#[^,]*,|",|' < azure_exports/$export > troubleshoot/$azureExport/azure.csv

echo 'Transform Azure export to JSON'
csv2json troubleshoot/$azureExport/azure.csv > troubleshoot/$azureExport/azure_0.json

echo 'Remove ` | Articles` in page name'
jq '.[].name |= (gsub(" \\| Articles"; ""))' troubleshoot/$azureExport/azure_0.json > troubleshoot/$azureExport/azure_2.json

echo 'Remove URLs in page name'
jq --arg siteUrl $siteUrl '.[].name |= (gsub(" - https://\($siteUrl)/"; ""))' troubleshoot/$azureExport/azure_2.json > troubleshoot/$azureExport/azure_3.json
jq --arg siteUrl $siteUrl '.[].name |= (gsub(" - \($siteUrl)/"; ""))' troubleshoot/$azureExport/azure_3.json > troubleshoot/$azureExport/azure_4.json

echo 'Change `url` object to `href` to match docfx.json structure'
jq '[.[] | with_entries(if .key == "url" then .key = "href" else . end)]' troubleshoot/$azureExport/azure_4.json > troubleshoot/$azureExport/azure_5.json

echo 'Duplicate URL key twice to create columns with product/version only (1) and article only (2) (both extracted from URL)'
jq '.[] | { fullUrl: .href, href: .href, name: .name, Ocurrences: .Ocurrences, subsite: .href }' troubleshoot/$azureExport/azure_5.json > troubleshoot/$azureExport/azure_6.json
jq -s . troubleshoot/$azureExport/azure_6.json > troubleshoot/$azureExport/azure_7.json

echo 'Remove everything but product and version from the URL (see 1 in comment above)'
jq --arg siteUrl $siteUrl '.[].subsite |= (gsub("https://\($siteUrl)/"; ""))' troubleshoot/$azureExport/azure_7.json > troubleshoot/$azureExport/azure_7a.json
jq '.[].subsite |= (gsub("/.*$"; ""))' troubleshoot/$azureExport/azure_7a.json > troubleshoot/$azureExport/azure_7b.json

echo 'Replace URL string'
jq --arg siteUrl $siteUrl '.[].href |= (gsub("https://https://\($siteUrl)/.*?/"; ""))' troubleshoot/$azureExport/azure_7b.json > troubleshoot/$azureExport/azure_7c.json

echo 'Removing entries of hits from sources like `localhost`, `http://127.0.0.1`, `hqcatalyst.local`, etc.'
jq --arg siteUrl $siteUrl 'del(..| objects | select(.fullUrl | contains("\($siteUrl)") | not))' troubleshoot/$azureExport/azure_7c.json > troubleshoot/$azureExport/azure.json

echo 'PART 3: Append Azure and DocFx data'

jq -s add troubleshoot/$azureExport/azure.json localIndexes/docfx.json > troubleshoot/$azureExport/merge.json

echo 'Site landing page (index.html) has a blank href - add the URL to its object so values for duplicate pages can be added in the next step'
echo 'Remove commas in names'
jq '
[.[] | walk(if type == "object" and .href == "" then .href = "index.html" else . end)]
| [.[] | (.name)|=(split(",")|join(""))]
' troubleshoot/$azureExport/merge.json > troubleshoot/$azureExport/merge_0.json

echo 'Add 0 views for docfx output'
jq 'walk(if type == "object" and .Ocurrences == null then .Ocurrences = "0" else . end)' troubleshoot/$azureExport/merge_0.json > troubleshoot/$azureExport/merge_1.json

echo 'Combine duplicates and sum values'
jq '
group_by(.href)[]
| group_by(.subsite)[]
| {fullUrl: .[0].fullUrl, href: .[0].href, name: .[0].name, Ocurrences: (map(.Ocurrences | tonumber) | add), subsite: .[0].subsite}
' troubleshoot/$azureExport/merge_1.json > troubleshoot/$azureExport/merge_2.json
jq -s '.' troubleshoot/$azureExport/merge_2.json > troubleshoot/$azureExport/merge_3.json

echo 'Assign tags, guide, and sub API guide from key_content.json'
jq 'sort_by(.url | -length) as $c | inputs | map(. + (.href as $s | first($c[] | select(.url as $ss | $s | index($ss))) // {}))' key_content.json troubleshoot/$azureExport/merge_3.json > troubleshoot/$azureExport/merge_4.json

echo 'PART 4: Clean up output'
echo 'Put in order so CSV is in order'
echo 'Lowercase name values because otherwise merge step below is case sensitive'
jq '
[.[] | { fullUrl: .fullUrl, subsite: .subsite, href: .href, name: .name, key: .url, guide: .guide, tag: .tag, restApiSubGuide: .restApiSubGuide, views: .Ocurrences }]
| map(.name |= ascii_downcase // .)
' troubleshoot/$azureExport/merge_4.json > troubleshoot/$azureExport/merge_5.json

echo 'Turn into CSV (optional - end with previous step for JSON output)'
jq -r '(.[0] | keys_unsorted), (.[] | to_entries|map(.value))|@csv' troubleshoot/$azureExport/merge_5.json > troubleshoot/$azureExport/merge_6.csv

echo 'Remove quotes around view values'
perl -ne 's/"(\d+)"/$1/g; print' < troubleshoot/$azureExport/merge_6.csv > final-$azureExport.csv
