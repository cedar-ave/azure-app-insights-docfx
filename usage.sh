#!/bin/bash

siteUrl="" #Example: docs.<my site>.com
storageAccountName="" #Azure Storage account name
accountKey="" #Azure Storage account key
containerName="" #Azure Storage container name
sourceFile="index.json"
indexesDir="siteIndexes"
blobFilesDir="blobFileIndex"
processingDir="processing"
sourceFilesDir="sourceFiles"

rm -rf $indexesDir
mkdir $indexesDir
rm -rf $indexesDir/$blobFilesDir
mkdir $indexesDir/$blobFilesDir
cd $indexesDir/$blobFilesDir

# Step 1: Uses `az storage` to get a list of all site files in the blob.
# Step 2: Locally filters that list to only files named index.json.
# Step 3: Uses `az storage` to get each file named index.json.

# API only returns 100 objects at a time so the `nextMarker` value is required. The first 100 objects requires no marker so that's the first use of `az storage`. The second use uses the markers. The loop exits when the marker is blank.

blobFileIndex () {
count=0
az storage fs file list -f $containerName --show-next-marker --recursive true --account-name $storageAccountName --account-key $accountKey > $count.json
marker=$(jq -r '.[] | select(if .nextMarker == null then empty else . end) | .nextMarker' $count.json)

while true; do
count=$(($count + 1))

az storage fs file list -f $containerName --show-next-marker --marker $marker --recursive true --account-name $storageAccountName --account-key $accountKey > $count.json
marker=$(jq -r '.[] | select(if .nextMarker == null then empty else . end) | .nextMarker' $count.json)

if [[ -z $marker ]]; then
return
fi

done
}
blobFileIndex

jq -s add [0-9]*.json > $blobFilesDir.json # If file = index.json then get it. In a loop

jq -r --arg sourceFile $sourceFile '
.[]
| select(.name != null)
| walk(if type == "object" and (.name | contains("\($sourceFile)") | not) then empty else . end)
| .name |= (gsub("/index.json"; ""))
| .name
' $blobFilesDir.json > $blobFilesDir.txt

cd ..

while read line ; do
filePath=`echo $line | tr -d '\r'`
fileName=`echo $line | tr -d '\r'` #prepare to accommodate index.json in subdirs (e.g., `site/subsite/index.json`)
if [[ $filePath =~ "/" ]]; then
fileName=`echo $filePath | sed 's|\/|-|g;'`
fi

az storage blob download --container-name $containerName --file $fileName.json --name $filePath/$sourceFile --account-key $accountKey --account-name $storageAccountName #download every index.json

jq --arg filePath $filePath '
.[] 
| { hrefSimple: .href, Name: .title, hrefSubsite: $filePath, hrefFull: "index only" }
| (.Id = "0")
| walk(if type == "object" and .hrefSimple == "" then .hrefSimple = "index.html" else . end)
' $fileName.json > temp.tmp && mv temp.tmp $fileName.json #add key for subsite only  #add `.hrefFull` key with `index only` value to all objects (to match a column in the Azure Analytics export)  #if `.hrefSimple` is blank, replace with `index.html` to indicate it is a landing page

done < $blobFilesDir/$blobFilesDir.txt

#combine all pages from each subsite into a single JSON file
jq -s . *.json > docfx.json 

cd ..

echo '*********************************'
echo "On to the Azure Analytics exports"
echo '*********************************'

rm -rf $processingDir
mkdir $processingDir

for type in content \
users ; do

csv2json $sourceFilesDir/$type.csv > $processingDir/$type.json

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
' keys/$key.json $processingDir/$type.json > temp.tmp && mv temp.tmp $processingDir/$type.json #add generic browser and OS keys (e.g., `Chrome` vs. `Chrome 106.0`) | standardize performance buckets into milliseconds (e.g., `5000` vs. `3sec-7sec`)

done

fi

articles="articles"
restapi="restapi"
api="api"

cat $processingDir/$type.json | \
jq --arg siteUrl $siteUrl --arg articles $articles --arg restapi $restapi --arg api $api '
[.[]
| with_entries(if .key == "Url" then .key = "hrefFull" else . end)
| .hrefFull |= split("?q=")[0]
| .hrefFull |= split("#")[0]
| .hrefFull |= (gsub("\\?$"; ""))
| .hrefFull |= (gsub("\/$"; ""))
| walk(if type == "object" and(.hrefFull | contains("\($siteUrl)") | not) then empty else . end)
| (.hrefSimple = .hrefFull)
| walk(if type == "object" and (.hrefSimple | contains("\/articles\/")) then (.hrefSimple |= "\($articles)" + split("\($articles)")[1]) else . end)
| walk(if type == "object" and (.hrefSimple | contains("\/restapi\/")) then (.hrefSimple |= "\($restapi)" + split("\($restapi)")[1]) else . end)
| walk(if type == "object" and (.hrefSimple | contains("\/api\/")) then (.hrefSimple |= "\($api)" + split("\($api)")[1]) else . end)
| walk(if type == "object" and (.hrefSimple | contains("index.html")) then (.hrefSimple = "index.html") else . end)
| walk(if type == "object" and (.hrefSimple | contains(".html") | not) then (.hrefSimple = "index.html") else . end)
| (.hrefSubsite = .hrefFull)
| .hrefSubsite |= split("https://\($siteUrl)/")[1]
| .hrefSubsite |= split("\($articles)")[0]
| .hrefSubsite |= split("\($restapi)")[0]
| .hrefSubsite |= split("\($api)")[0]
| .hrefSubsite |= (gsub("\/$"; ""))
| .hrefSubsite |= (gsub("/index.html"; ""))
| .Name |= (gsub(" - https://\($siteUrl)/"; ""))
| .Name |= (gsub(" - \($siteUrl)/"; ""))]
' > temp.tmp && mv temp.tmp $processingDir/$type.json #remove search result and anchor strings from `.hrefFull` | remove `localhost`, etc. | create a simple path to join on (`articles/guide/page.html`) | if `.hrefSimple` is blank, replace with `index.html` to indicate it is a landing page | add key for subsite only

if [[ $type = "content" ]]
then
jq '.[]' $processingDir/$type.json > temp.tmp && mv temp.tmp $processingDir/$type.json
jq '.[]' $indexesDir/docfx.json > temp.tmp && mv temp.tmp $processingDir/docfx.json
jq -s . $processingDir/docfx.json $processingDir/$type.json > temp.tmp && mv temp.tmp $processingDir/$type.json
#merge docfx.json and content.json
fi

jq '
[.[]
| .Name |= (gsub(" \\| Articles"; ""))
| .Name |= (gsub("!"; ""))
| (.Name) |= (split(",")|join(""))
| (.Name) |= ascii_downcase]
' $processingDir/$type.json > temp.tmp && mv temp.tmp $processingDir/$type.json # remove unnecessary appendages to article name (e.g. ` | Articles`) | remove exclamation marks from page name | lowercase page name | remove commas from page name

if [[ $type = "content" ]]
then
cat $processingDir/$type.json | \
jq '
[group_by(.hrefSimple)[]
| group_by(.hrefSubsite)[]
| {hrefFull: .[0].hrefFull, hrefSimple: .[0].hrefSimple, Name: .[0].Name, views: (map(.Id | tonumber) | add), hrefSubsite: .[0].hrefSubsite}]
| sort_by(-.views)
' > temp.tmp && mv temp.tmp $processingDir/$type.json #combine duplicates | sum values

jq '
sort_by(.path | -length) as $c | inputs | map(. + (.hrefSimple as $s | first($c[] | select(.path as $ss | $s | index($ss))) // {}))
' keys/contentKey.json $processingDir/$type.json > temp.tmp && mv temp.tmp $processingDir/$type.json #assign tags, guide, & sub API guide from `contentKey.json`

cat $processingDir/$type.json | \
jq -S '
[.[]
| del(.path)]
' > temp.tmp && mv temp.tmp $processingDir/$type.json

fi

cp $processingDir/$type.json .

done
