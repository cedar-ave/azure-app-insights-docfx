# Optimize usage analytics reports of a DocFx website tracked with Azure Application Insights

This project standardizes and adds value to usage data about site content and users. Final output is two JSON files optimized for use in data visualization software.

- [Prerequisites](#prerequisites)
  - [Directory and site structure](#directory-and-site-structure)
    - [Local machine](#local-machine)
    - [Azure Blob structure](#azure-blob-structure)
    - [Live site](#live-site)
  - [Setup and tools](#setup-and-tools)
- [Overview](#overview)
  - [Purpose 1: Identify site pages with zero views](#purpose-1-identify-site-pages-with-zero-views)
    - [(1) List of all pages that exist](#1-list-of-all-pages-that-exist)
    - [(2) List of pages tracked by Azure Application Insights](#2-list-of-pages-tracked-by-azure-application-insights)
    - [How the lists are compared](#how-the-lists-are-compared)
      - [Azure Application Insights](#azure-application-insights)
      - [index.json](#indexjson)
      - [Output](#output)
    - [Combine duplicates and sums their values](#combine-duplicates-and-sums-their-values)
      - [Search results and anchors](#search-results-and-anchors)
      - [Same page, different names](#same-page-different-names)
      - [Subsite landing pages](#subsite-landing-pages)
      - [Irrelevant domains](#irrelevant-domains)
        - [Example](#example)
    - [Page name inconsistencies](#page-name-inconsistencies)
  - [Purpose 2: Add metadata to site pages](#purpose-2-add-metadata-to-site-pages)
    - [Example](#example-1)
      - [`contentKey.json`](#contentkeyjson)
      - [Example output](#example-output)
  - [Purpose 3: Gather data by individual page view](#purpose-3-gather-data-by-individual-page-view)
    - [Combine duplicates](#combine-duplicates)
    - [Standardize browsers](#standardize-browsers)
    - [Standardize operating systems](#standardize-operating-systems)
    - [Standardize performance buckets](#standardize-performance-buckets)
- [Steps](#steps)
  - [Step 1: Export data from Azure Application Insights](#step-1-export-data-from-azure-application-insights)
  - [Step 2: Process the data](#step-2-process-the-data)
  - [Final output](#final-output)
- [Notes](#notes)

## Prerequisites

### Directory and site structure

#### Local machine

One site generated by DocFx per guide on a local machine (or build pipeline), e.g.:

```plaintext
source/
  product-guide-1/
    articles/
      page-1.md
      page-2.md
    templates/
    docfx.json
    index.md
    Etc.
  product-guide-2/
    articles/
      page-1.md
      page-2.md
    templates/
    docfx.json
    index.md
    Etc.
  product-guide-2a/
    articles/
      page-1.md
      page-2.md
    templates/
    docfx.json
    index.md
    Etc.
  index.md
```

Running DocFx on each directory produces:

```plaintext
source/
  product-guide-1/
    _site/
      articles/
        page-1.html
        page-2.html
      index.html
  product-guide-2/
    _site/
      articles/
        page-1.html
        page-2.html
      index.html
  product-guide-2a/
    _site/
      articles/
        page-1.html
        page-2.html
      index.html
```

#### Azure Blob structure

Contents of each local directory are published to a corresponding directory in an Azure Blob (nested directories are supported), e.g.:

Azure Storage Account > Container > Blob:

```plaintext
blob/
  product-guide-1/
    articles/
      page-1.html
      page-2.html
    index.html
  product-guide-2/
    articles/
      page-1.html
      page-2.html
    index.html
    product-guide-2a/
      articles/
        page-1.html
        page-2.html
      index.html
  index.html
```

#### Live site

Files in the Azure Blob are published to the live site following the Azure Blob's directory structure, e.g.:

```plaintext
www.<your site>.com/index.html
www.<your site>.com/product-guide-1/index.html
www.<your site>.com/product-guide-1/articles/page-1.html
www.<your site>.com/product-guide-1/articles/page-2.html
www.<your site>.com/product-guide-2/index.html
www.<your site>.com/product-guide-2/articles/page-1.html
www.<your site>.com/product-guide-2/articles/page-2.html
www.<your site>.com/product-guide-2/product-guide-2a/articles/page-1.html
www.<your site>.com/product-guide-2/product-guide-2a/articles/page-2.html
www.<your site>.com/product-guide-2/product-guide-2a/index.html
```

### Setup and tools

- [JavaScript code for Azure Application Insights tracking](https://learn.microsoft.com/en-us/azure/azure-monitor/app/usage-overview) at the bottom of each site page
  - To do this, add the code snippet in a `scripts.tmpl.partial` file in a [custom DocFx template](https://dotnet.github.io/docfx/tutorial/howto_create_custom_template.html#merge-template-with-default-template)
- [DocFx](https://dotnet.github.io/docfx/index.html)
- [jq](https://stedolan.github.io/jq/download)
- Azure Storage Account and Blob
- The Azure Blob's:
  - Storage Account name
  - Account key
  - Container name
- Site root URL

## Overview

### Purpose 1: Identify site pages with zero views

Azure Application Insights provides data only site pages with >=1 view, e.g.:

```csv
url,name,Ocurrences
"https://<your site>.com/product-guide-1/index.html","Welcome",1600
"http://localhost:3000/product-guide-1/index.html","Welcome",1550
"https://<your site>.com/product-guide-1/page-1.html","Settings",1425
"https://<your site>.com/product-guide-1/page-2.html","Configuration | Articles",1420
"https://<your site>.com/product-guide-2/page-1.html","Glossary",1415
"https://<your site>.com/product-guide-2/page-1.html","Glossary - docs.<your site>.com",1413
"http://localhost:7000/product-guide-2/page-1.html","Glossary",1412
"https://<your site>.com/product-guide-2/page-2.html?q=admin%20console","Administration",1400
"https://<your site>.com/product-guide-1/page-1.html#options","Settings",1390
"https://<your site>.com/product-guide-2/product-guide-2a/page-1.html","Intro",1375
"https://<your site>.com/product-guide-2/page-3.html","Security, permissions, and identification",1350
```

It can be helpful to know which pages have zero views.

The solution is to compare a (1) list of all pages that exist with a (2) list of pages tracked by Azure Application Insights. Any page not in both lists is assumed to have zero views.

#### (1) List of all pages that exist

When a DocFx site is generated locally (e.g., `<local machine>/product-guide-1/_site/**`), an `index.json` file is produced in `_site`. `index.json` lists all pages in the site.

`index.json` is deployed to the Azure Blob with the rest of the site (e.g., Azure Storage Account > Container > Blob > `product-guide-1/index.json`.

#### (2) List of pages tracked by Azure Application Insights

A Kusto query (`kusto_queries/content.kusto`) returns a list of pages with >=1 view. It also returns each page's view count, name, and URL. See step 2 below.

#### How the lists are compared

`usage.sh` uses the Azure CLI to download the `index.json` file from each directory (subsite) in the Azure Blob.

First, it combines each directory's (and any subdirectory's) `index.json` files into one JSON file (list 1). Next, the CSV exported from Azure Application Insights (list 2) is transformed to a JSON file. Finally, the script compares the two JSON files on URL, which is included in both lists. Pages in list 1 not included in list 2 are assumed to have zero views.

Before the comparison, the script also sums the value of page views for duplicate pages and addresses other irregularities.

##### Azure Application Insights

| page   | views |
|--------|-------|
| page-1 | 1300  |
| page-2 | 1200  |
| page-2 | 300   |
| page-4 | 200   |

##### index.json

| page   |
|--------|
| page-1 |
| page-2 |
| page-3 |
| page-4 |

##### Output

| page   | views |
|--------|-------|
| page-1 | 1300  |
| page-2 | 1500  |
| page-3 | 0     |
| page-4 | 200   |

#### Combine duplicates and sums their values

Azure Application Insights data includes data for duplicate pages. `usage.sh` combines duplicate pages and sums their views.

##### Search results and anchors

Pages reached via search results and anchors are combined and view counts summed, e.g. (for a unique guide):

- Search: `page-1.html` (800 views) and `page-1?=settings` (100 views) are merged and become `page-1.html` (900 views)
- Anchor: `page-2.html` (700 views) and `page-2.html#anchor` (50 views) are merged and become `page-2.html` (750 views)

##### Same page, different names

Pages with different names that are actually the same page are combined and view counts summed, e.g.:

| Page name in export                               | Views |
|---------------------------------------------------|-------|
| `About Product 1`                                 | 100   |
| `About Product 1 - https://docs.<your site>.com/` | 30    |
| `About Product 1 - docs.<your site>.com/`         | 200   |
| `About Product 1 \| Articles`                     | 50    |
| `About Product 1 \|Articles`                      | 10    |

becomes

| Page name in report | Views |
|---------------------|-------|
| `About Product 1`   | 390   |

##### Subsite landing pages

`usage.sh` consolidates views of a subsite's landing page. Some have a blank URL, others have a title of `index.html`, etc.

##### Irrelevant domains

`usage.sh` removes pages not on the `docs.<your site>.com` domain, e.g.:

###### Example

| Domain in export       | Views |
|------------------------|-------|
| `docs.<your site>.com` | 1000  |
| `http://127.0.0.1`     | 200   |
| `0.0.0.0`              | 100   |
| `localhost`            | 500   |
| `C:/Users`             | 100   |

becomes

| Domain in export       | Views |
|------------------------|-------|
| `docs.<your site>.com` | 1000  |

#### Page name inconsistencies

- Standardizes the case of page names, which is different for list 1 and list 2
- Removes commas in page names

### Purpose 2: Add metadata to site pages

Reporting can be enhanced when pages are categorized by guide names, tags, type of documentation (how-to, about, API reference, API conceptual, etc.), etc. It can also help to identify which pages are landing pages, etc.

If the path in the `hrefFull` key in `content.json` (object 1) includes the string in the `path` key in `contentKey.json` (object 2), all keys in object 2 are added to object 1.

#### Example

##### `contentKey.json`

```json
[
  {
    "path": "product-guide-1/",
    "guide": "product-guide-1",
    "tag": "how-to"
  },
  {
    "path": "product-guide-2/articles/home.html",
    "guide": "product-guide-2",
    "tag": "home-page"
  },
  {
    "path": "/api/",
    "guide": "api",
    "restApiSubGuide": identity,
    "tag": "restApireference"
  }
]
```

##### Example output

```json
[
  {
    "guide": "product-guide-1",
    "hrefFull": "https://docs.<your site>.com/product-guide-1/articles/page-1.html",
    "hrefSimple": "articles/product-guide-1/page-1.html",
    "hrefSubsite": "product-guide-1",
    "name": "page 1",
    "tag": "how-to",
    "views": 780
  },
  {
    "guide": "product-guide-1",
    "hrefFull": "https://docs.<your site>.com/product-guide-1/articles/page-2.html",
    "hrefSimple": "articles/product-guide-1/page-2.html",
    "hrefSubsite": "product-guide-1",
    "name": "page 2",
    "tag": "how-to",
    "views": 625
  },
  {
    "guide": "product-guide-2",
    "hrefFull": "https://docs.<your site>.com/product-guide-2/articles/home.html",
    "hrefSimple": "product-guide-2/articles/home.html",
    "hrefSubsite": "product-guide-2",
    "name": "welcome",
    "tag": "home-page",
    "views": 550
  },
  {
    "guide": "api",
    "hrefFull": "https://docs.<your site>.com/api/identity/ping.html",
    "hrefSimple": "api/identity/ping.html",
    "hrefSubsite": "api",
    "name": "Ping",
    "restApiSubGuide": identity,
    "tag": "restApireference",
    "views": 410
  },
  {
    "guide": "api",
    "hrefFull": "https://docs.<your site>.com/api/identity/feature-toggles.html",
    "hrefSimple": "api/identity/feature-toggles.html",
    "hrefSubsite": "api",
    "name": "feature toggles",
    "restApiSubGuide": identity,
    "tag": "restApireference",
    "views": 300
  }
]
```

\* `guide` vs. `subsite`: `guide` is useful if the site directory setup is `.../subsite/articles/product-guide-2/page-1.html`.

### Purpose 3: Gather data by individual page view

In Azure Application Insights, a Kusto query (`kusto_queries/users.kusto`) returns the following data on each page view, e.g.:

```csv
"timestamp [UTC]",name,url,"user_Id",duration,"client_City","client_StateOrProvince","client_CountryOrRegion","client_Browser","client_OS","session_Id",itemType,"operation_Id",performanceBucket,"count_sum"
"10/30/2022, 7:54:05.267 PM","Page 1","https://docs.<your site>.com/product-guide-1/articles/page-1.html",abcd,511,Auburn,Washington,"United States","Chrome 106.0","Mac OS X 10.15","abc1234",pageView,abc1234,"500ms-1sec",1
"10/29/2022, 10:50:00.100 AM","Page 1","https://docs.<your site>.com/product-guide-1/articles/page-1.html",abcd,520,Cleveland,Ohio,"United States","Chrome 105.0","Windows 10","abc1234",pageView,abc1234,"500ms-1sec",1
"10/29/2022, 10:48:00.001 AM","Ping","https://docs.<your site>.com/api/identity/ping.html",abcd,520,Tokyo,,Japan,"Firefox 106.0","Android","abc1234",pageView,abc1234,"3sec-7sec",1
```

#### Combine duplicates

`usage.sh` resolves the following issues in the export:

- [Duplicate pages due to search results and anchors](#search-results-and-anchors)
- [Same page, different names](#same-page-different-names)
- [Irrelevant domains](#irrelevant-domains)

#### Standardize browsers

Similar to the method using [`contentKey.json`](#purpose-2-add-metadata-to-site-pages) to add metadata to pages, a `browserKey.json` file standardizes browser names based on specified strings, e.g.:

```json
[
    {
        "browserKey": "Edg",
        "browserGeneral": "Edge"
    },
    {
        "browserKey": "Mobile Safari",
        "browserGeneral": "Safari Mobile"
    }
]
```

If the browser reported by Azure Application Insights is `Edg`, `usage.sh` identifies from `osBrowser.json` that `Edg` includes the string `Edg` (as named in `osBrowser`) and adds an `osBrowser` category.  

#### Standardize operating systems

The Azure Application Insights export may include operating systems like:

- `Windows 8.1`
- `Windows 10`
- `Mac OS X 10.13`
- `Mac OS X 10.15`
- `iOS 15.6`
- `iOS 15.7`
- `Linux`
- `Android`
- Etc.

It can be helpful to understand the operating systems used on a brand level instead of a detailed version.

A `osKey.json` file reduces the longer version name to a brand name based on a string in the version name, e.g.:

```
[
    {
        "osKey": "Windows",
        "osGeneral": "Windows"
    },
    {
        "osKey": "Mac OS",
        "osGeneral": "Mac OS"
    }
]
```

If the operating system reported by Azure Application Insights is `Windows 10`, `usage.sh` identifies from `osKey.json` that `Windows 10` includes the string `Windows` (as named in `osKey`) and adds an `osGeneral` category.  

#### Standardize performance buckets

Reporting visualization software may have trouble recognizing the duration of a page's performance due to how the duration is reported in the Azure Application Insights export.

`usage.sh` replaces the values with a consistent value in milliseconds, e.g.:

- `<250ms` becomes `100`
- `500ms-1sec` becomes `750`
- `>=5min` becomes `300000`
- Etc.

`performanceKey.json`:

```json
[
    {
        "performanceBucketKey": "1sec-3sec",
        "performanceBucketMilliseconds": "2000"
    },
    {
        "performanceBucketKey": "250ms-500ms",
        "performanceBucketMilliseconds": "350"
    },
    {
        "performanceBucketKey": "500ms-1sec",
        "performanceBucketMilliseconds": "750"
    }
]
```

## Steps

### Step 1: Export data from Azure Application Insights

1. Go to Azure Application Insights > `Logs`.
2. Copy and paste the contents of `kusto_queries/content.kusto` into the query field.
3. Click `Run`.
4. Export all rows as a CSV file to a local `azure_exports` directory.
5. Rename the exported file according to the table below.
6. Repeat steps for `kusto_queries/users.kusto`.

| Kusto query                 | Rename the export to |
|-----------------------------|----------------------|
| kusto_queries/content.kusto | content.csv          |
| kusto_queries/users.kusto   | users.csv            |

### Step 2: Process the data

1. In `usage.sh`, define the empty variables, e.g.:

```
storageAccountName="" #Azure Storage account name
accountKey="" #Azure Storage account key
containerName="" #Azure Storage container name
siteUrl="" #Example: docs.<my site>.com
```

2. In `dirsKey.json`, add directory names and paths in the Azure Blob, e.g.:

```
[
  {
    "blobDirName": "product-guide-1",
    "blobDirPath": "product-guide-1"
  },
  {
    "blobDirName": "product-guide-1a",
    "blobDirPath": "product-guide-1/product-guide-1a"
  }
]
```

3. Execute the script locally:

```
./usage.sh
```

### Final output

- `content.json`
- `users.json`

## Notes

- By default, Azure Application Insights stores only 90 days of data.
- Why the scripts transform the data from CSV to JSON: The Azure Application Insights export is CSV. `index.json` in the Azure Blob is JSON. Combining the two data sources as JSON enables cleaner processing and sums values of consolidated pages.
