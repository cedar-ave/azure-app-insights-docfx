#!/bin/bash

siteUrl="" #Example: docs.<my site>.com
storageAccountName="" #Azure Storage account name
accountKey="" #Azure Storage account key
containerName="" #Azure Storage container name
sourceFile="index.json"

if [[ -d localIndexes ]]; then
    rm -rf localIndexes
fi #remove directory if exists from previous run
mkdir localIndexes

if [[ -d process ]]; then 
    rm -rf process
fi #remove directory if exists from previous run
mkdir process

echo '********************************'
echo "Starting with DocFx JSON output"
echo '********************************'

jq -r '.[] | "\(.blobDirName)|\(.blobDirPath)"' keys/dirsKey.json |
    while IFS="|" read -r blobDirName blobDirPath; do

for dir in $blobDirName ; do
blobName=`echo $blobDirName | tr -d '\r'`
blobPath=`echo $blobDirPath | tr -d '\r'`

az storage blob download --container-name $containerName --file localIndexes/$blobName.json --name $blobPath/$sourceFile --account-key $accountKey --account-name $storageAccountName #download index.json from each blob directory named in keys/dirsKey.json

jq --arg blobDirName $blobDirName '
.[] 
| { hrefSimple: .href, name: .title, hrefSubsite: $blobDirName, hrefFull: "index only" }
| (.Ocurrences = "0")
| walk(if type == "object" and .hrefSimple == "" then .hrefSimple = "index.html" else . end)
' localIndexes/$blobDirName.json > temp.tmp && mv temp.tmp localIndexes/$blobDirName.json #add key for subsite only  #add `.hrefFull` key with `index only` value to all objects (to match a column in the Azure Analytics export)  #if `.hrefSimple` is blank, replace with `index.html` to indicate it is a landing page

done
done

jq -s . localIndexes/*.json > process/docfx.json #combine all pages from each subsite into a single JSON file

echo '*********************************'
echo "On to the Azure Analytics exports"
echo '*********************************'

for type in content \
users ; do

csv2json azure_exports/$type.csv > temp.tmp && mv temp.tmp process/$type.json

if [[ -f *.json ]]; then
    rm *.json
fi #remove final output file if exists

if [[ $type = "users" ]]
then

for key in browserKey \
osKey \
performanceBucketKey ; do

if [[ $key = browserKey ]]
then
sourceKey="client_Browser"
fi

if [[ $key = osKey ]]
then
sourceKey="client_OS"
fi

if [[ $key = performanceBucketKey ]]
then
sourceKey="performanceBucket"
fi

jq --arg key $key --arg sourceKey $sourceKey '
sort_by('".$key"' | -length) as $c | inputs | map(. + ('".$sourceKey"' as $s | first($c[]
| select('".$key"' as $ss | $s | index($ss))) // {}))
' keys/$key.json process/$type.json > temp.tmp && mv temp.tmp process/$type.json #add generic browser and OS keys (e.g., `Chrome` vs. `Chrome 106.0`)  #standardize performance buckets into milliseconds (e.g., `5000` vs. `3sec-7sec`)

done

fi

cat process/$type.json | \
jq --arg siteUrl $siteUrl '
[.[]
| with_entries(if .key == "url" then .key = "hrefFull" else . end)
| .hrefFull |= split("?q=")[0]
| .hrefFull |= split("#")[0]
| walk(if type == "object" and(.hrefFull | contains("\($siteUrl)") | not) then empty else . end)
| .hrefFull |= (gsub("\/$"; ""))
| (.hrefSimple = .hrefFull)
| .hrefSimple |= (gsub("https://\($siteUrl)/.*?/"; ""))
| walk(if type == "object" and (.hrefSimple | endswith(".html") | not) then .hrefSimple = "index.html" else . end)
| (.hrefSubsite = .hrefFull)
| .hrefSubsite |= (gsub("https://\($siteUrl)/"; ""))
| .hrefSubsite |= (gsub("/.*$"; ""))
| .name |= (gsub(" \\| Articles"; ""))
| .name |= (gsub(" - https://\($siteUrl)/"; ""))
| .name |= (gsub(" - \($siteUrl)/"; ""))
| .name |= (gsub("!"; ""))
| (.name) |= (split(",")|join(""))
| (.name) |= ascii_downcase]
' > temp.tmp && mv temp.tmp process/$type.json #remove search result and anchor strings from `.hrefFull`  #remove `localhost`, etc.  #create a simple path to join on (`articles/guide/page.html`)  #if `.hrefSimple` is blank, replace with `index.html` to indicate it is a landing page  #add key for subsite only  #remove unnecessary appendages to article name (e.g. ` | Articles`)  #remove exclamation marks from page name  #lowercase page name  #remove commas from page name

if [[ $type = "users" ]]
then
cat process/$type.json | \
jq -S '
[.[]
| with_entries(if .key == "timestamp [UTC]" then .key = "timestamp" else . end)
| with_entries(if .key == "client_Browser" then .key = "browser" else . end)
| with_entries(if .key == "client_City" then .key = "city" else . end)
| with_entries(if .key == "client_CountryOrRegion" then .key = "countryOrRegion" else . end)
| with_entries(if .key == "client_OS" then .key = "os" else . end)
| with_entries(if .key == "client_StateOrProvince" then .key = "stateOrProvince" else . end)
| with_entries(if .key == "count_sum" then .key = "views" else . end)
| del(.browserKey,.osKey,.performanceBucketKey,.itemType)]
' > temp.tmp && mv temp.tmp process/$type.json #simplify & standardize keys
fi

if [[ $type = "content" ]]
then

jq -s add process/$type.json process/docfx.json > temp.tmp && mv temp.tmp process/$type.json #merge docfx.json and azure.json

cat process/$type.json | \
jq '
[group_by(.hrefSimple)[]
| group_by(.hrefSubsite)[]
| {hrefFull: .[0].hrefFull, hrefSimple: .[0].hrefSimple, name: .[0].name, views: (map(.Ocurrences | tonumber) | add), hrefSubsite: .[0].hrefSubsite}]
| sort_by(-.views)
' > temp.tmp && mv temp.tmp process/$type.json #combine duplicates  #sum values

jq '
sort_by(.path | -length) as $c | inputs | map(. + (.hrefSimple as $s | first($c[] | select(.path as $ss | $s | index($ss))) // {}))
' keys/contentKey.json process/$type.json > temp.tmp && mv temp.tmp process/$type.json #assign tags, guide, & sub API guide from `contentKey.json`

cat process/$type.json | \
jq -S '
[.[]
| del(.path)]
' > temp.tmp && mv temp.tmp process/$type.json

fi

cp process/$type.json .

done
