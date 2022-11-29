# Optimize usage analytics reports of a DocFx website tracked with Azure Application Insights

This project standardizes and adds value to usage data about site content and users. Final output is are CSVs optimized for use in data visualization software.

- [Prerequisites](#prerequisites)
  - [Directory and site structure](#directory-and-site-structure)
  - [Setup and tools](#setup-and-tools)
- [Overview](#overview)
  - [Script 1: Content analytics](#script-1-content-analytics)
    - [Purpose 1: Identify site pages with zero views](#purpose-1-identify-site-pages-with-zero-views)
    - [Purpose 2: Add metadata to content (guide names, tags, type of documentation, landing pages, etc.)](#purpose-2-add-metadata-to-site-pages)
  - [Script 2: User analytics](#script-2-user-analytics)
- [Steps](#steps)
- [Notes](#notes)

## Prerequisites

### Directory and site structure

#### Local machine

One site generated by DocFx per guide on a local machine (or build pipeline), e.g.:

```
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

```
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


  - **product-guide-1/** in the Azure Blob is **\<site root\>/product-guide-1/**\*\*
    - Example: **docs.\<your site\>.com/product-guide-1/articles/page-1.html**
  - **product-guide-2/** in the Azure Blob is **\<site root\>/product-guide-2/**\*\*
    - Example: **docs.\<your site\>.com/product-guide-2/articles/page-1.html**


#### Azure Blob structure

Contents of each local directory are published to a corresponding directory in an Azure Blob (nested directories are supported), e.g.:

Azure Storage Account > Container > Blob:

```
wwwroot/
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

```
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
  - To do this, add the code snippet in **scripts.tmpl.partial** in a [custom DocFx template](https://dotnet.github.io/docfx/tutorial/howto_create_custom_template.html#merge-template-with-default-template)
- [DocFx](https://dotnet.github.io/docfx/index.html)
- [jq](https://stedolan.github.io/jq/download)
- [csv2json](https://www.npmjs.com/package/csv2json)
- Azure Storage Account and Blob
- The Azure Blob's:
  - Storage Account Name
  - Account Key
  - Container Name
- Site root URL

## Overview

### Script 1: Content analytics

> **script_content.sh**

#### Purpose 1: Identify site pages with zero views

Azure Application Insights provides data only site pages with >=1 view. It can be helpful to know which pages have zero views.

The solution is to compare a (1) list of all pages that exist with a (2) list of pages tracked by Azure Application Insights. Any page not in both lists is assumed to have zero views.

##### (1) List of all pages that exist

When a DocFx site is generated locally (e.g., \<local machine\>/**product-guide-1/_site/**\*\*), an **index.json** file is produced in **_site**. **index.json** lists all pages in the site.

**index.json** is deployed to the Azure Blob with the rest of the site (e.g., Azure Storage Account > Container > Blob > **product-guide-1/index.json**.

##### (2) List of pages tracked by Azure Application Insights

A Kusto query (**kusto_content.kusto**) returns a list of pages with >=1 view. It also returns each page's view count, name, and URL. See step 2 below.

##### How the lists are compared

**script_content.sh** uses the Azure CLI to pull the **index.json** file from each directory (subsite) in the Azure Blob.

First, it combines all the **index.json** files into one JSON file (list 1). Next, the CSV exported from Azure Application Insights (list 2) is transformed to a JSON file. Finally, the script compares the two JSON files on URL, which is included in both lists. Pages in list 1 not included in list 2 are assumed to have zero views.

Before the comparison, the script also sums the value of page views for duplicate pages and addresses other irregularities.

###### Azure Application Insights

| page   | views |
|--------|-------|
| page-1 | 1300  |
| page-2 | 1200  |
| page-2 | 300   |
| page-4 | 200   |

###### index.json

| page   |
|--------|
| page-1 |
| page-2 |
| page-3 |
| page-4 |

###### Final output

| page   | views |
|--------|-------|
| page-1 | 1300  |
| page-2 | 1500  |
| page-3 | 0     |
| page-4 | 200   |

##### Combines duplicates and sums their values

Azure Application Insights data includes data for duplicate pages. **script_content.sh** combines duplicate pages and sums their views.

###### Search results and anchors

Pages reached via search results and anchors are combined and view counts summed, e.g. (for a unique guide):

  - Search: **page-1.html** (800 views) and **page-1?=settings** (100 views) are merged and become **page-1.html** (900 views)
  - Anchor: **page-2.html** (700 views) and **page-2.html#anchor** (50 views) are merged and become **page-2.html** (750 views)

###### Same page, different names

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

###### Subsite landing pages

**script_content.sh** consolidates views of a subsite's landing page. Some have a blank URL, others have a title of **index.html**, etc.

###### Irrelevant domains

**script_content.sh** removes pages not on the **docs.\<your site\>.com** domain, e.g.:

#### Example

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

###### Misc

- Standardizes the case of page names, which is different for list 1 and list 2
- Removes commas in page names

#### Purpose 2: Add metadata to site pages

Reporting can be enhanced when pages are categorized by guide names, tags, type of documentation (how-to, about, API reference, API conceptual, etc.), etc. It can also help to identify which pages are landing pages, etc.

A **key.json** file adds the categorizations to pages in the final report. Categories are applied when the page's URL contains specified strings.

###### Example of key.json

```
[
  {
    "url": "/product-guide-1/",
    "guide": "product-guide-1",
    "restApiSubGuide": null,
    "tag": "how-to"
  },
  {
    "url": "/product-guide-2/home.html",
    "guide": "product-guide-2",
    "restApiSubGuide": null,
    "tag": "home-page"
  },
  {
    "url": "/api/",
    "guide": "api",
    "restApiSubGuide": identity,
    "tag": "restApireference"
  }
]
```

###### Example output (simplified version of final output)

```
"url","guide","restApiSubGuide","tag","views"
"https://docs.<your site>.com/product-guide-1/articles/page.html","product-guide-1",,"how-to",2500
"https://docs.<your site>.com/product-guide-2/articles/page.html","product-guide-2",,"site-page",800
"https://docs.<your site>.com/api/identity/entities.html","api","identity","restApiReference",700
```

### Script 2: User analytics

> **script_users.sh**

In Azure Application Insights, a Kusto query (**kusto_users.kusto**) returns the following data on each page view: 

- Timestamp
- Page view
- User ID
- Duration
- Location
- Browser
- Operating system
- Session ID
- Item type
- Operation ID
- Performance bucket

#### Combines duplicates

**script_users.sh** resolves the following issues in the export:
- [Duplicate pages due to search results and anchors](search-results-and-anchors)
- [Same page, different names](same-page-different-names)
- [Irrelevant domains](irrelevant-domains)

#### Standardizes performance buckets

Reporting visualization software may have trouble recognizing the duration of a page's performance due to how the duration is reported in the Azure Application Insights export. 

**script_users.sh** replaces the values with a consistent value in milliseconds, e.g.:

- `<250ms` becomes `100`
- `500ms-1sec` becomes `750`
- `>=5min` becomes `300000`
- Etc.

#### Standardizes browsers

Similar to [**key.json**](purpose-2-add-metadata-to-site-pages), a **key_browser.json** file standardizes browser names based on specified strings, e.g.:

```
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

#### Standardizes operating systems

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

It can be helpful to understand the browsers being used on a wider brand level rather than a detailed version. 

A **key_browser.json** file reduces the longer version name to a brand name based on a string in the version name, e.g.:

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

Meaning that If the operating system reported by Azure Application Insights is `Windows 10`, **script_users.sh** identifies from **key_browser.json** that `Windows 10` includes the string `Windows` (as named in `osKey`) and adds an `osGeneral` category.  

#### Example output (simplified version of final output)

```
"date","name","browser","browserGeneral","osKey","osGeneral"
"10/24/2022, 7:24:32.475 PM","Welcome to Product 1 Docs","Chrome 106.0","Chrome","Mac OS X 10.15","Mac OS"
```

## Steps

### Step 1: Export data from Azure Application Insights

1. Go to Azure Application Insights > Logs.
2. Copy and paste the contents of **kusto_content.kusto** into the query field.
3. Click **Run**.
4. Export all rows as a CSV file to a local **azure_exports** directory.
5. Rename the exported file according to the table below.
6. Repeat steps for **kusto_users.kusto**.

| Script  | Kusto query         | Rename the export to |
|---------|---------------------|----------------------|
| Content | kusto_content.kusto | content.csv          |
| Users   | kusto_users.kusto   | users.csv            |

## Step 2: Process the data

1. In **script_content.sh**, define the empty variables, e.g.:

```
storageAccountName="" #Azure Storage account name
accountKey="" #Azure Storage account key
containerName="" #Azure Storage container name
sourceFile="index.json" #Default DocFx output
siteUrl="" #Example: docs.<my site>.com
```

2. In **script_content.sh**, add the top-level directory names in the Azure Blob under `for sourceDir`, e.g.:

```
for sourceDir in product-guide-1 \
product-guide-2 \
product-guide-3 ; do
```

3. In **script_content.sh**, add variables for any nested directories (e.g., **product-guide-1/product-guide-1a/**\*\*), e.g.:

```
if [ $sourceDir = "product-guide-1" ]; then
subSourceDir="product-guide-1a"
```



Execute each script locally:

```
./script_content.sh
./script_users.sh
```

Results:

- final-content.csv
- final-users.csv
- troubleshoot/

## Notes
- By default, Azure Application Insights stores only 90 days of data.
- Why the scripts transform the data from to CSV to JSON: The Azure Application Insights export is CSV. **index.json** in the Azure Blob is JSON. Combining the two data sources as JSON enables cleaner processing and sums values of consolidated pages.
