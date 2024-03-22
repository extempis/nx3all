# NX3ALL

![Issues](https://img.shields.io/github/issues-raw/extempis/nx3all)
![Pull requests](https://img.shields.io/github/issues-pr-raw/extempis/nx3all)
![Total downloads](https://img.shields.io/github/downloads/extempis/nx3all/total.svg)
![GitHub forks](https://img.shields.io/github/forks/extempis/nx3all?label=fork&style=plastic)
![GitHub watchers](https://img.shields.io/github/watchers/extempis/nx3all?style=plastic)
![GitHub stars](https://img.shields.io/github/stars/extempis/nx3all?style=plastic)
![License](https://img.shields.io/github/license/extempis/nx3all)
![Repository Size](https://img.shields.io/github/repo-size/extempis/nx3all)
![Contributors](https://img.shields.io/github/contributors/extempis/nx3all)
![Commit activity](https://img.shields.io/github/commit-activity/m/extempis/nx3all)
![Last commit](https://img.shields.io/github/last-commit/extempis/nx3all)
![Release date](https://img.shields.io/github/release-date/extempis/nx3all)
![Latest Production Release Version](https://img.shields.io/github/release/extempis/nx3all)

Tools for backup and restore nexus 3 repository

This tool can download all artifacts and some settings from a Nexus3 repository server.
And upload them to another server or the same in case of corruption or disaster.

## Installation

### linux 

#### With a rpm package

```bash
$ rpm -ivh nx3all-<version>-1.rpm
```
#### With a deb package

```bash
$ dpkg -i nx3all-<version>.deb
```

#### On other OS 

Install using the tarball file.

```bash
$ tar -C /usr/local/bin/ --strip-components=1 -xvf nx3all-<version>.tar.gz 
```

### Windows 

#### Prerequis

- bash
- curl
- sha256sum/sha1sum
- jq 
  
Install gitbash or cygwin 

To install jq on gitbash

```bash
curl -L -o /usr/bin/jq.exe https://github.com/stedolan/jq/releases/latest/download/jq-win64.exe
```

To install nx3all

```bash
$ tar -C /usr/local/bin/ --strip-components=1 -xvf nx3all-<version>.tar.gz 
```

## Configuration

### To download artifacts

Create a user in Nexus3 and assign the following roles:

* `nx-repository-view-*-*-browse`
* `nx-repository-view-*-*-read`

### To upload artifacts

In order to upload artifacts, additional privileges are required:

* `nx-repository-view-*-*-add`
* `nx-repository-view-*-*-edit`

### To read/write configuration

In order to do admin stuff, additional privileges are required:

TODO

## Usage

### Check the help menu

```bash
user@oo:~/backup_dir$ nx3all -h

-------------------------------
Setup
-------------------------------
In order to avoid passing the login/password pair as an argument each time, this tool uses the ~/.netrc file.

Credential setup :
  $ nx3all login https://nexus_url.domain
-------------------------------

-------------------------------
Usage
-------------------------------
  # Get tool's version
  $ nx3all.bash version

  # List all repositories
  $ nx3all.bash list -u nexus_url
    $ nx3all.bash list -u https://nexus.domain/nexus

  # Backup configuration
  $ nx3all.bash backupcfg -u nexus_url
    $ nx3all.bash backupcfg -u https://nexus.domain/nexus

  # Restore Configuration
  $ nx3all.bash restorecfg -u nexus_url
    $ nx3all.bash restorecfg -u https://nexus.domain/nexus

  # Backup, dump all artifacts in all repositories
  $ nx3all.bash backup -u nexus_url --all
    $ nx3all.bash backup -u https://nexus.domain/nexus --all

  # Backup, dump all artifacts in specifics repositories
  # limitation : repositories of type 'group' are not backup, just 'proxy' or 'hosted' are allowed
  $ nx3all.bash backup -u nexus_url -s repo1
  $ nx3all.bash backup -u nexus_url -s repo1,repo2,repo3
    $ nx3all.bash backup -u https://nexus.domain/nexus -s maven,raw-files,npm-proxy

  # Backup only files that match a filter
    $ nx3all.bash backup -u https://nexus.domain/nexus -s raw-files  --filter "/version/"

  # Restore artifacts
  $ nx3all.bash restore -u nexus_url -s source_dir -d nexus-repo-name
      $ nx3all.bash restore -u https://nexus.domain/nexus -s ./dl/maven -d maven-central

  # Get metadata only for one repository
  $ nx3all.bash metadata -u nexus_url -s nexus-repo-name
      $ nx3all.bash metadata -u https://nexus.domain/nexus -s maven-central

  # Create default usefull tasks
  $ nx3all.bash task -u nexus_url -c
      $ nx3all.bash task -u https://nexus.domain/nexus -c

  # List all tasks
  $ nx3all.bash task -u nexus_url -l
      $ nx3all.bash task -u https://nexus.domain/nexus -l

  # Invalidate all repositories cache
  $ nx3all.bash invalidatecache -u nexus_url -a
      $ nx3all.bash task -u https://nexus.domain/nexus -l

  # Invalidate cache for some repositories
  $ nx3all.bash invalidatecache -u nexus_url -s maven,raw-files,npm-proxy
      $ nx3all.bash task -u https://nexus.domain/nexus -l

  Note:
    Behind a proxy, you must set environment variables :
    on linux:   http_proxy/https_proxy
    on windows: HTTP_PROXY/HTTPS_PROXY

```
### To Work behind a proxy

A way to pass the proxy address is to set environment variables :

On Linux

```bash
export http_proxy="[protocol://][host][:port]"
export https_proxy="[protocol://][host][:port]"
```

On windows 

```bash
export HTTP_PROXY="[protocol://][host][:port]"
export HTTPS_PROXY="[protocol://][host][:port]"
```

To disable global proxy settings, unset these two environment variables.

```bash
unset http_proxy
unset https_proxy
```

## Supported

| type      | backup | restore |
|-----------|--------|---------|
| docker    |        |         |
| maven2    | x      | x       | 
| npm       | x      | x       | 
| pypi      | x      | x       |
| raw       | x      | x       |
| yum       | x      | x       | 

## Unsupported

- S3 blob store configuration.

## Roadmap 

- backup/restore configuration : ldap,role,privilege,certificates
- backup/restore verify integrity with sha256 (save sha256 to file)
- backup/restore container registry
- improve progress status
- Add a option to trust self signed certificates
- use curlrc file to make Curl use a proxy

## License

[![License](https://img.shields.io/badge/License-Apache_2.0-yellowgreen.svg)](https://opensource.org/licenses/Apache-2.0)

Copyright 2022 exTempis
