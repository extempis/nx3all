#!/bin/bash

#   Copyright 2022 exTempis

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

VERSION=0.0.0
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

LOGERROR=`mktemp`
POSTPONE_TMP=
trap 'rm -fr $LOGERROR $POSTPONE_TMP output.json' EXIT

CMD=
DIR_PREFIX="$PWD/dl"
DESTINATION=
SOURCE=
ARGS_LIST=
BASE_URL=
ARCHIVE=
CHECK_INTEGRITY=
OPTION_LIST=false
OPTION_CREATE=false
OPTION_REMOVE_ALL=false

_spin="/-\|"
_spini=0

_RESET=$(tput sgr0)
_GREEN=$(tput setaf 2)
_BLUE=$(tput setaf 4)
_RED=$(tput setaf 1)
_YELLOW=$(tput setaf 3)
_WHITE=$(tput setaf 7)
ERASETOEOL="\033[K"

SUCCES=200
CLIENT_ERROR=400
UNAUTHORIZED=401
FORBIDDEN=403
NOTFOUND=404
SERVER_ERROR=500
SERVER_TMOUT=504

CURL="curl -k -n -s "

usage () {
    cat <<HELP_USAGE
    version: $VERSION

    Copyright 2022 exTempis 
    License Apache 2.0

    -------------------------------
    Setup
    -------------------------------
    In order to avoid passing the login/password pair as an argument each time, 
    this tool uses the ~/.netrc file.

    Credential setup :
      $ $(basename $0) login https://nexus_url.domain
    -------------------------------

    -------------------------------
    Usage
    -------------------------------
    # Get tool's version
    $ $(basename $0) version

    # List all repositories 
    $ $(basename $0) list -u nexus_url
      $ $(basename $0) list -u https://nexus.domain/nexus

    # Backup configuration
    $ $(basename $0) backupcfg -u nexus_url
      $ $(basename $0) backupcfg -u https://nexus.domain/nexus

    # Restore Configuration
    $ $(basename $0) restorecfg -u nexus_url 
      $ $(basename $0) restorecfg -u https://nexus.domain/nexus 

    # Backup, dump all artifacts in all repositories
    $ $(basename $0) backup -u nexus_url --all
      $ $(basename $0) backup -u https://nexus.domain/nexus --all

    # Backup, dump all artifacts in specifics repositories
    # ${_YELLOW}limitation${_RESET} : repositories of type 'group' are not backup, just 'proxy' or 'hosted' are allowed
    $ $(basename $0) backup -u nexus_url -s repo1
    $ $(basename $0) backup -u nexus_url -s repo1,repo2,repo3
      $ $(basename $0) backup -u https://nexus.domain/nexus -s maven,raw-files,npm-proxy

    # Restore artifacts
    $ $(basename $0) restore -u nexus_url -s source_dir -d nexus-repo-name
        $ $(basename $0) restore -u https://nexus.domain/nexus -s ./dl/maven -d maven-central

    # Get metadata only 
    $ $(basename $0) metadata -u nexus_url -s nexus-repo-name
        $ $(basename $0) metadata -u https://nexus.domain/nexus -s maven-central

    # Create default usefull tasks
    $ $(basename $0) task -u nexus_url -c
        $ $(basename $0) task -u https://nexus.domain/nexus -c

    # List all tasks
    $ $(basename $0) task -u nexus_url -l
        $ $(basename $0) task -u https://nexus.domain/nexus -l

    # Invalidate all repositories cache
    $ $(basename $0) invalidatecache -u nexus_url -a
        $ $(basename $0) task -u https://nexus.domain/nexus -l

    # Invalidate cache for some repositories
    $ $(basename $0) invalidatecache -u nexus_url -s maven,raw-files,npm-proxy
        $ $(basename $0) task -u https://nexus.domain/nexus -l

    Note:
      Behind a proxy, you must set environment variables :
      on linux:   http_proxy/https_proxy 
      on windows: HTTP_PROXY/HTTPS_PROXY 

HELP_USAGE
}

parse_args() {
  # parsing verb
  case "$1" in
    "login")
      BASE_URL=$(echo ${2%/})
      init_credentials
      ;;
    "list")
      CMD="LIST"
      ;;
    "backup")
      CMD="BACKUP"
      ;;
    "backupcfg")
      CMD="BACKUP_CFG"
      ;;
    "restore")
      CMD="RESTORE"
      ;;
    "restorecfg")
      CMD="RESTORE_CFG"
      ;;
    "delete")
      CMD="DELETE"
      ;;
    "invalidatecache")
      CMD="CACHE"
      ;;
    "task")
      CMD="TASK"
      ;;
    "metadata")
      CMD="METADATA"
      ;;
    "version")
      echo "Version : $VERSION"
      exit 0
      ;;
    *) 
      usage
      exit 1
      ;;
  esac
  shift
  
  VALID_ARGS=$(getopt -o crliau:s:d:p:hz --long metadata:,remove,list,create,integrity:,all,zip,url:,source:,destination:,prefix:,help -- "$@")
  if [[ $? -ne 0 ]]; then
      exit 1;
  fi
  #[[ $# -eq 0 ]] && usage && exit 0

  eval set -- "$VALID_ARGS"
  while [ : ]; do
    case "$1" in
      -u | --url)
          BASE_URL=$(echo ${2%/})
          shift 2
          ;;
      -a | --all)
          ARGS_LIST="--all"
          shift
          ;;
      -i | --integrity)
          CHECK_INTEGRITY='y'
          shift
          ;;
      -s | --source)
          SOURCE="$2"
          ARGS_LIST="$2"
          shift 2
          ;;
      -d | --destination)
          DESTINATION="$2"
          shift 2
          ;;
      -p | --prefix)
          DIR_PREFIX="$(realpath $2)"
          shift 2
          ;;
      -h | --help)
          echo "Version : $VERSION"
          usage
          shift
          ;;
      -z | --zip)
          ARCHIVE=true
          shift
          ;;
      -l | --list)
          OPTION_LIST=true
          shift
          ;;
      -c | --create)
          OPTION_CREATE=true
          shift
          ;;
      -r | --remove)
          OPTION_REMOVE_ALL=true
          shift
          ;;
      --) shift; 
        break 
        ;;
      *) shift;
          echo "${_RED}Error:${_RESET} Unknow flag: $2"
          exit 1
          ;;
    esac
  done
}

progressbar () {
  _string=$1

  (( ${#_string} > 40 )) && _string="${_string:0:37}..."

  global_percent=$(("$2*100/$3*100"/100))
  global_progress=$(("${global_percent}*4"/10))
  global_remainder=$((40-global_progress))
  global_completed=$(printf "%${global_progress}s")
  global_left=$(printf "%${global_remainder}s")
  _spinf=$_spin

  # double progress bar
  if [ ! -z "${4}" ]
  then 
    _percent=$(("$4*100/$5*100"/100))
    _progress=$(("${_percent}*4"/10))
    _remainder=$((40-_progress))
    _completed=$(printf "%${_progress}s")
    _left=$(printf "%${_remainder}s")
    [ $_percent -eq 100 ] && _spinf="#"
    printf "\r%-40s [%s] %3s%% | [%s] %3s%%" "${_string}" "${global_completed// /#}${_spinf:_spini++%${#_spinf}:1}${global_left// /-}" ${global_percent} "${_completed// /#}${_spinf:_spini++%${#_spinf}:1}${_left// /-}" ${_percent}
  else
    [ $global_percent -eq 100 ] && _spinf="#"
    printf "\r%-40s [%s] %3s%% " "${_string}" "${global_completed// /#}${_spinf:_spini++%${#_spinf}:1}${global_left// /-}" ${global_percent}
  fi
}

init_credentials() {
  # Verify inputs
  [ -z "$BASE_URL" ] && usage && echo "${_RED}Missing nexus url${_RESET}" && exit 1

  #Get user lgin/password
  read -p 'Username: ' username
  read -sp 'Password: ' password
  echo

  # Try first if the credential is correct
  HTTP_STATUS=$($CURL -o /dev/null -w "%{http_code}" -u $username:$password -X 'GET' $BASE_URL'/service/rest/v1/repositories' -H 'accept: application/json')
  if [ $? -ne 0 ] || [ ${HTTP_STATUS} -ne ${SUCCES} ]
  then
    echo -e "Error: ${_RED}invalid${_RESET} username/password (http_code $HTTP_STATUS)"
    exit 1
  fi
  echo -e "Login ${_GREEN}Succeeded!${_RESET}"

  #Record information to netrc file
  touch ~/.netrc
  chmod 0600 ~/.netrc
  hostname=$(echo "$BASE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
  content=$(cat ~/.netrc | grep -v "machine $hostname login $username ")
  echo "$content" > ~/.netrc
  echo "machine $hostname login $username password $password" >> ~/.netrc
  echo -e "The crendential is stored in ~/.netrc."

  exit 0
}

getAllpage() {
  repository=$1
  CNT_REPO=$2
  NB_REPOS=$3
  iter=1
  pad=`printf %010d $iter`
  _string="Get information for $repository"
  (( ${#_string} > 40 )) && _string="${_string:0:37}..."

  METADIR=$DIR_PREFIX/.metadata/$repository
  rm -fr $METADIR
  mkdir -p $METADIR

  resu=$($CURL -o "$METADIR/$repository$pad.json" -X 'GET' $BASE_URL'/service/rest/v1/components?repository='$repository -H 'accept: application/json')
  NB_ITEMS=$(jq '.items|length' "$METADIR/$repository$pad.json")
  [ "$NB_ITEMS" -eq "0" ] && printf "\r%-40s %s$ERASETOEOL\n" "$_string" "[${_YELLOW}SKIP${_RESET}]" && rm -f "$METADIR/$repository$pad.json" && return

  while :
  do
    progressbar "Get information for $repository" $CNT_REPO $NB_REPOS
    
    continuationToken=$(jq -r .continuationToken "$METADIR/$repository$pad.json")
    [ "$continuationToken" == "null" ] && break

    iter=$(( iter + 1 ))
    pad=`printf %010d $iter`
    HTTP_STATUS=$($CURL -o "$METADIR/$repository$pad.json" -w "%{http_code}" -X 'GET' $BASE_URL'/service/rest/v1/components?repository='$repository'&continuationToken='$continuationToken -H 'accept: application/json')
    [ "$HTTP_STATUS" != "200"  ] && echo "Receive HTTP_STATUS=$HTTP_STATUS" && rm -f "$METADIR/$repository$pad.json"
  done
  #jq -n '{ items : [ inputs.items ] | add}' `ls $METADIR/$repository*.json` > $METADIR/$repository.json
  printf "\r%-40s %s$ERASETOEOL\n" "$_string" "[${_GREEN}COMPLETE${_RESET}]" && return
}

integrity() {
  if [ "$CHECK_INTEGRITY" == "y" ]
  then
    if [ "$sha256" != "null" ]
    then
      SHA=$(sha256sum $(dirname $path)/$name | awk '{print $1}')
      [ "$SHA" != $sha256 ] && echo "Error: sha256 for $name in repository $repository" >> $LOGERROR && NB_FILE_KO=$((NB_FILE_KO + 1)) && integrity_resu=1
    else
      if [ "$sha1" != "null" ]
      then
        SHA=$(sha1sum $(dirname $path)/$name | awk '{print $1}')
        [ "$SHA" != $sha1 ] && echo "Error: sha1 for $name in repository $repository" >> $LOGERROR && NB_FILE_KO=$((NB_FILE_KO + 1)) && integrity_resu=1 
      else
        echo "Error: impossible to verify integrity for $name in repository $repository" >> $LOGERROR && NB_FILE_KO=$((NB_FILE_KO + 1)) && integrity_resu=1 
      fi
    fi
  fi
}

wget_item () {
  LOG=$(mkdir -p `dirname $path` 2>&1)
  RS=$?
  integrity_resu=0

  [ $RS -ne 0 ] && echo "Error: mkdir failed for $name in repository $repository : $downloadUrl ($LOG)" >> $LOGERROR && NB_FILE_KO=$((NB_FILE_KO + 1)) &&return
  [ $NB_REPOS -eq 1 ]  && progressbar "dl $repository $name" "$iter" "$TOTAL_ITEMS"
  [ $NB_REPOS -gt 1 ] && progressbar "dl $repository $name" "$CNT_REPO" "$NB_REPOS" "$iter" "$TOTAL_ITEMS"

  if [ -f "$(dirname $path)/$name" ]; then
    integrity 
  else
    LOG=$($CURL -o $(dirname "$path")/"$name" "$downloadUrl" 2>&1)
    RS=$?
    [ $RS -ne 0 ] && echo "Error: wget failed for $name in repository $repository : $downloadUrl ($LOG)" >> $LOGERROR && NB_FILE_KO=$((NB_FILE_KO + 1)) && return
    integrity 
  fi
  [ $integrity_resu -eq 0 ] && NB_FILE_OK=$((NB_FILE_OK + 1))
}

download() {
  repository=$1
  restore=$PWD
  CNT_REPO=$2
  NB_REPOS=$3
  TOTAL_ITEMS=0
  iter=1
  NB_FILE_OK=0
  NB_FILE_KO=0
  METADIR=$DIR_PREFIX/.metadata/$repository

  LIST=$(find $METADIR -maxdepth 1 -name "$repository*.json")
  [ -z "$LIST" ] && printf "\r%-40s %s$ERASETOEOL\n" "dl $repository" "[${_YELLOW}SKIP${_RESET}](${_BLUE}$TOTAL_ITEMS${_RESET})" && return

  TOTAL_ITEMS=$(cat $METADIR/$repository*.json | grep downloadUrl | wc -l)
  [ $TOTAL_ITEMS -eq 0 ] && printf "\r%-40s %s$ERASETOEOL\n" "dl $repository" "[${_YELLOW}SKIP${_RESET}](${_BLUE}$TOTAL_ITEMS${_RESET})" && return

  mkdir -p "$DIR_PREFIX/$repository"
  cd "$DIR_PREFIX/$repository"

  POSTPONE_TMP=`mktemp`

  for file in $LIST
  do
    objs=$(jq -c ".items[].assets[]" $file | jq -s .)
    length=$(jq ".|length" <<<$objs)
    length=$(( length -1 ))
    for i in `seq 0 $length`
    do
      downloadUrl=$(jq -r ".[$i].downloadUrl" <<<$objs)
      name=$( basename "$downloadUrl" | tr -d '"' )
      path=$(jq -r ".[$i].path" <<<$objs)
      contentType=$(jq  ".[$i].contentType" <<<$objs)
      sha1=$(jq -r ".[$i].checksum.sha1" <<<$objs)
      sha256=$(jq -r ".[$i].checksum.sha256" <<<$objs)

      # we postpone html file
      if [ "$contentType" != "text/html" ]
      then
        wget_item
      else
        echo "$name $downloadUrl $path $sha1 $sha256" >> $POSTPONE_TMP
      fi
      iter=$(( iter + 1 ))
    done
  done
  while read name downloadUrl path sha1 sha256
  do
    wget_item 
  done < $POSTPONE_TMP
  rm -f $POSTPONE_TMP
  [ $NB_FILE_OK == $TOTAL_ITEMS ] && printf "\r%-40s %s$ERASETOEOL\n" "dl $repository" "[${_GREEN}COMPLETE${_RESET}](${_BLUE}$TOTAL_ITEMS${_RESET})"
  [ $NB_FILE_OK != $TOTAL_ITEMS ] && printf "\r%-40s %s$ERASETOEOL\n" "dl $repository" "[${_YELLOW}INCOMPLETE${_RESET}](${_BLUE}$TOTAL_ITEMS${_RESET}-${_RED}$NB_FILE_KO${_RESET}=${_GREEN}$NB_FILE_OK${_RESET})"
  cd $restore
}

backup() {
  # Verify inputs
  [ -z "$ARGS_LIST" ] && usage && echo "${_RED}Error:${_RESET} Missing repositories list to backup" && exit 1

  mkdir -p $DIR_PREFIX/.metadata
  
  LIST=$(list)
  FORMAT=$(echo "$LIST" | grep "^$DESTINATION\ " | awk '{print $3}' )
  
  for item in ${ARGS_LIST//,/ }
  do
    case "$item" in
      --all)
        echo "Backup all repositories"
        resu=$($CURL -X 'GET' $BASE_URL'/service/rest/v1/repositories' -H 'accept: application/json')
        names=$(echo $resu | jq -r '.[] |  select(.type != "group") | "\(.name)"' | sort)
        NB=$(echo $names | wc -w)
        i=1
        for r in $names
        do
          getAllpage $r $i $NB
          i=$(( i + 1 ))
        done
        echo ""
        i=1
        for r in $names
        do
          download $r $i $NB
          i=$(( i + 1 ))
        done
        ;;
      *)
        echo ""
        echo "Backup repository : $item"
        getAllpage $item 0 1
        download $item 0 1
        ;;
    esac
  done
  echo "The backup location : $DIR_PREFIX"
}

list() {
  TEMP=`mktemp`
  HTTP_STATUS=$($CURL -o $TEMP -w "%{http_code}" -X 'GET' $BASE_URL'/service/rest/v1/repositories' -H 'accept: application/json')
  if [ $? -ne 0 ] || [ ${HTTP_STATUS} -ne ${SUCCES} ]
  then
    echo -e "${_RED}Error:${_RESET} Can not list repositories (http_code $HTTP_STATUS)"
    rm $TEMP
    exit 1
  fi
  cat "$TEMP" | jq -r '.[] | "\(.name) \t \(.type) \t \(.format) "' | sort |awk '{printf("%-30s %-20s %s \n", $1, $2, $3)}'
  rm $TEMP
}

ping() {
  # Verify inputs
  [ -z "$BASE_URL" ] && usage && echo "${_RED}Missing nexus url${_RESET}" && exit 1

  HTTP_STATUS=$($CURL -o /dev/null -w "%{http_code}" -X 'GET' $BASE_URL'/service/rest/v1/repositories' -H 'accept: application/json')
  if [ $? -ne 0 ] || [ ${HTTP_STATUS} -ne ${SUCCES} ]
  then
    echo -e "${_RED}Error:${_RESET} Can not access nexus 3 repository"
    exit 1
  fi
  echo -e "Ping nexus repository : [${_GREEN}OK${_RESET}]"
}

compress () {
  [ -z "$ARCHIVE" ] && return 
  tar cf $PWD/nexus3all-$(date '+%Y-%m-%d').tar -C $DIR_PREFIX .
}

restore_raw() {
  cd $SOURCE
  OIFS="$IFS"
  IFS=$'\n'
  FIND=$(find . -type f | sed "s|^\./||")
  for file in $FIND
  do
     file_url=$(echo $file | sed 's/ /%20/g')
     curl -nks -X PUT --upload-file "$file" "${BASE_URL}/repository/$DESTINATION/$file_url"
  done
  cd -
  IFS="$OIFS"
}

restore_api() {
  KIND=$1
  cd $SOURCE
  LIST=$(find . -type f -printf '%P\n')
  for file in $LIST
  do
    echo `basename $file`
    if [ "$KIND" == "pypi" ] ||  [ "$KIND" == "npm" ] 
    then
      $CURL -X 'POST'  ${BASE_URL}'/service/rest/v1/components?repository='$DESTINATION \
          -H 'accept: application/json'\
          -H 'Content-Type: multipart/form-data'\
          -F $KIND'.asset=@'$file 
    else
      $CURL -X 'POST'  ${BASE_URL}'/service/rest/v1/components?repository='$DESTINATION \
          -H 'accept: application/json'\
          -H 'Content-Type: multipart/form-data'\
          -F $KIND'.asset=@'$file \
          -F $KIND'.asset.filename='$file
    fi
  done
  cd -
}

restore() {
  # Verify inputs
  [ -z "$SOURCE" ] && usage && echo "${_RED}Error:${_RESET} Missing source folder!" && exit 1
  [ -z "$DESTINATION" ] && usage && echo "${_RED}Error:${_RESET} Missing the destination nexus repository!" && exit 1

  SOURCE="$(realpath $SOURCE)"

  LIST=$(list)
  TYPE=$(echo "$LIST" | grep "^$DESTINATION\ " | awk '{print $2}' )
  FORMAT=$(echo "$LIST" | grep "^$DESTINATION\ " | awk '{print $3}' )

  [ "$TYPE" != "hosted" ] && echo "${_RED}Error:${_RESET} Impossible to upload to the repository ${_BLUE}$DESTINATION${_RESET} because it is not a ${_GREEN}'hosted'${_RESET} type but a ${_RED}'$TYPE'${_RESET} type" && exit 1
  case "$FORMAT" in
    "raw")
      restore_raw
      ;;
    "maven2")
      restore_raw
      ;;
    "pypi")
      restore_api pypi
      ;;
    "yum")
      restore_api yum
      ;;
    "npm")
      restore_api npm
      ;;
    *) 
      echo "${_RED}Error:${_RESET} Unsupported repository format : $FORMAT"
      exit 1
      ;;
  esac
}

backup_config (){
  mkdir -p ${DIR_PREFIX}/config
  while read -r repo type format
  do
    echo ">$repo $type $format"
    [ "$format" == "maven2" ] && format="maven"
    $CURL -X 'GET' "${BASE_URL}/service/rest/v1/repositories/$format/$type/$repo" \
                  -o "${DIR_PREFIX}/config/${repo}_config.json" \
                  -H 'accept: application/json' 
  done < <(list)
  set +x
}

restore_config(){
  curlArgsPost=('-X' "POST" '-H' "accept: application/json" '-H' "Content-Type: application/json")
  curlArgsGet=('-X' "GET" '-H' "Content-Type: application/json")
  curlArgsPut=('-X' "PUT" '-H' "accept: application/json" '-H' "Content-Type: application/json")
  grplist="" 
  for file in `ls ${DIR_PREFIX}/config/*.json`
  do 
    name=$(jq -r '.name' $file)
    blob=$(jq -r '.storage.blobStoreName' $file)
    format=$(jq -r '.format' $file)
    [ "$format" == "maven2" ] && format="maven"
    typ=$(jq -r '.type' $file)
    if [ "$typ" == "group" ]
    then
      grplist+=" $file"
    else
      echo -e "\tCreate blob store : $blob for repository $name"
      json="{  \"path\": \"$blob\",  \"name\": \"$blob\" }"
      HTTP_CODE=$($CURL "${curlArgsPost[@]}" -w "%{http_code}" -o res.json ${BASE_URL}/service/rest/v1/blobstores/file -d "$json")
      [ ${HTTP_CODE} -ge 400 ] && echo -e "\t\t$_RED`jq -r '.[0].message' res.json`$_RESET"
      echo -e "\tCreate config for $name : format=$format type=$typ"
      HTTP_CODE=$($CURL "${curlArgsPost[@]}" -w "%{http_code}" -o res.json ${BASE_URL}/service/rest/v1/repositories/$format/$typ -d "$(< $file)")
      [ ${HTTP_CODE} -ge 400 ] && echo -e "\t\t$_RED`cat res.json`$_RESET"
      $CURL "${curlArgsPut[@]}"  ${BASE_URL}/service/rest/v1/repositories/$format/$typ -d "$(< $file)"
      rm res.json
    fi
  done
  # create groups after 
  for file in $grplist
  do 
    name=$(jq -r '.name' $file)
    blob=$(jq -r '.storage.blobStoreName' $file)
    format=$(jq -r '.format' $file)
    [ "$format" == "maven2" ] && format="maven"
    typ=$(jq -r '.type' $file)
    echo -e "\tCreate blob store : $blob for repository $name"
    json="{  \"path\": \"$blob\",  \"name\": \"$blob\" }"
    HTTP_CODE=$($CURL "${curlArgsPost[@]}" -w "%{http_code}" -o res.json ${BASE_URL}/service/rest/v1/blobstores/file -d "$json")
    [ ${HTTP_CODE} -ge 400 ] && echo -e "\t\t$_RED`jq -r '.[0].message' res.json`$_RESET"
    echo -e "\tCreate config for $name : format=$format type=$typ"
    HTTP_CODE=$($CURL "${curlArgsPost[@]}" -w "%{http_code}" -o res.json ${BASE_URL}/service/rest/v1/repositories/$format/$typ -d "$(< $file)")
    [ ${HTTP_CODE} -ge 400 ] && echo -e "\t\t$_RED`cat res.json`$_RESET"
    $CURL "${curlArgsPut[@]}"  ${BASE_URL}/service/rest/v1/repositories/$format/$typ -d "$(< $file)"
    rm res.json
  done
}

destroy_all(){
  read -p "Are you sure to delete all repositories ? " -n 1 -r
  echo    # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    curlArgsDel=('-X' "DELETE" '-H' "accept: application/json" )

    # Remove all existing repo
    $CURL -X 'GET' ${BASE_URL}/service/rest/v1/repositories -H 'accept: application/json' -o output.json
    jq -c '.[]' output.json | while read i; do
      name=$(echo $i | jq -r '.name')
      $CURL "${curlArgsDel[@]}"  ${BASE_URL}/service/rest/v1/repositories/$name
      printf "%-10s %-40s $_GREEN[deleted]$_RESET\n"  Repository $name 
    done
    rm -f .output.json
    #delete blobs
    $CURL -X 'GET' ${BASE_URL}/service/rest/v1/blobstores -H 'accept: application/json' -o output.json
    jq -c '.[]' output.json | while read i; do
      name=$(echo $i | jq -r '.name')
      $CURL "${curlArgsDel[@]}"  ${BASE_URL}/service/rest/v1/blobstores/$name
      printf "%-10s %-40s $_GREEN[deleted]$_RESET\n"  Blob $name
    done
    rm -f .output.json
  fi
}

delete_content() {
  [ -z "$ARGS_LIST" ] && usage && echo "${_RED}Error:${_RESET} Missing repositories list to delete contents" && exit 1
  
  mkdir -p $DIR_PREFIX/.metadata
  for repository in ${ARGS_LIST//,/ }
  do
    LIST=$(list)
    TYPE=$(echo "$LIST" | grep "^$repository\ " | awk '{print $2}' )
    [[ "$TYPE" != "hosted" && "$TYPE" != "proxy" ]] && echo "${_RED}Error:${_RESET} Impossible to delete contents from the repository ${_BLUE}$repository${_RESET} ${_BLUE}$DESTINATION${_RESET} because it is not a ${_GREEN}'hosted or proxy'${_RESET} type but a ${_RED}'$TYPE'${_RESET} type" && continue

    read -p "Are you sure you want to delete the content of the repository : $repository ? " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      nb_file=0
      TOTAL_ITEMS=0
      getAllpage $repository 0 1

      LIST=$(find $METADIR -maxdepth 1 -name "$repository*.json")
      [ -z "$LIST" ] && printf "\r%-40s %s$ERASETOEOL\n" "Remove content for $repository" "[${_YELLOW}SKIP${_RESET}](${_BLUE}$TOTAL_ITEMS${_RESET})" && continue

      TOTAL_ITEMS=$(cat $METADIR/$repository*.json | grep downloadUrl | wc -l)
      [ $TOTAL_ITEMS -eq 0 ] && printf "\r%-40s %s$ERASETOEOL\n" "Remove content for $repository" "[${_YELLOW}SKIP${_RESET}](${_BLUE}$TOTAL_ITEMS${_RESET})" && continue

      for file in $LIST
      do
        objs=$(jq -c ".items[]" $file | jq -s .)
        length=$(jq ".|length" <<<$objs)
        length=$(( length -1 ))
        for i in `seq 0 $length`
        do
          id=$(jq -r ".[$i].id" <<<$objs)
          name=$(jq -r ".[$i].name" <<<$objs)
          $CURL -X 'DELETE' $BASE_URL"/service/rest/v1/components/$id"   -H 'accept: application/json' > /dev/null
          nb_file=$(( nb_file + 1 ))
          progressbar "Remove contents for  $repository $name" "$nb_file" "$TOTAL_ITEMS"
        done
      done

      _string="Remove content for $repository"
      (( ${#_string} > 40 )) && _string="${_string:0:37}..."
      printf "\r%-40s %s$ERASETOEOL\n" "$_string" "[${_GREEN}COMPLETE${_RESET}]"
    fi
  done
}

invalidateCache() {
  LIST=$(list)
  if [[ "$ARGS_LIST" == '--all' ]]
  then
    REPOS=$(echo "$LIST" | grep -v "hosted" | awk '{print $1}' )
    for repository in ${REPOS}
    do
      HTTP_CODE=$($CURL -w "%{http_code}" -X 'POST' \
              ${BASE_URL}"/service/rest/v1/repositories/$repository/invalidate-cache" \
              -H 'accept: application/json')
      [[ ${HTTP_CODE} -ne 204 ]] && echo -e "Invalidate cache for $repository failed with code $HTTP_CODE"
      [[ ${HTTP_CODE} -eq 204 ]] && echo -e "Invalidate cache for $repository ${_GREEN}Succeeded!${_RESET}"
    done
  else
    for repository in ${ARGS_LIST//,/ }
    do
      TYPE=$(echo "$LIST" | grep "^$repository" | awk '{print $2}' )
      [[ "$TYPE" = "hosted" ]] && echo "${_RED}Error:${_RESET} Impossible to invalidate cache for the repository ${_BLUE}$repository${_RESET} ${_BLUE}$DESTINATION${_RESET} because it is not a ${_GREEN}'group or proxy'${_RESET} type but a ${_RED}'$TYPE'${_RESET} type" && continue
      # Proxy or group repositories only.
      HTTP_CODE=$($CURL -w "%{http_code}" -X 'POST' \
              ${BASE_URL}"/service/rest/v1/repositories/$repository/invalidate-cache" \
              -H 'accept: application/json')
      [[ ${HTTP_CODE} -ne 204 ]] && echo -e "Invalidate cache for $repository failed with code $HTTP_CODE"
      [[ ${HTTP_CODE} -eq 204 ]] && echo -e "Invalidate cache for $repository ${_GREEN}Succeeded!${_RESET}"
    done
  fi
}

delete() {
  if [[ $ARGS_LIST == '--all' ]]
  then
    destroy_all
  else
    delete_content
  fi
}

task() {
  LIST=$(list)
  YUM_REPOS_NAME=$(echo "$LIST" | grep yum | awk '{print $1}')
  BLOB=$($CURL -X 'GET' \
    ${BASE_URL}'/service/rest/v1/blobstores' \
    -H 'accept: application/json')

  bck='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"db.backup","enabled":true,"name":"admin-backup-database","alertEmail":"","notificationCondition":"FAILURE","schedule":"daily","properties":{"location":"/nexus-data/backup"},"recurringDays":[],"startDate":"2023-01-01T22:00:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":134}'
  docker='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"repository.docker.upload-purge","enabled":true,"name":"docker-delete-incomplete-uploads","alertEmail":"","notificationCondition":"FAILURE","schedule":"weekly","properties":{"age":"72"},"recurringDays":[7],"startDate":"2023-01-18T08:15:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":137}'
  npm='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"repository.npm.rebuild-metadata","enabled":true,"name":"repair-all-npm-metadata","alertEmail":"","notificationCondition":"FAILURE","schedule":"daily","properties":{"repositoryName":"*","packageName":""},"recurringDays":[],"startDate":"2023-01-18T20:00:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":195}'
  browse='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"create.browse.nodes","enabled":true,"name":"repair-rebuild-all-repo-browse","alertEmail":"","notificationCondition":"FAILURE","schedule":"daily","properties":{"repositoryName":"*"},"recurringDays":[],"startDate":"2023-01-18T20:00:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":146}'
  search='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"repository.rebuild-index","enabled":true,"name":"repair-rebuild-all-repo-search","alertEmail":"","notificationCondition":"FAILURE","schedule":"daily","properties":{"repositoryName":"*"},"recurringDays":[],"startDate":"2023-01-18T20:00:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":152}'

  yum='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"repository.yum.rebuild.metadata","enabled":true,"name":"repair-rebuild-yum-metadata","alertEmail":"","notificationCondition":"FAILURE","schedule":"daily","properties":{"repositoryName":"dr-yum-hosted","yumMetadataCaching":"false"},"recurringDays":[],"startDate":"2023-01-18T20:00:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":158}'
  cpt='{"action":"coreui_Task","method":"create","data":[{"id":"","typeId":"blobstore.compact","enabled":true,"name":"compact-blob-raw-hosted2","alertEmail":"","notificationCondition":"FAILURE","schedule":"weekly","properties":{"blobstoreName":"raw-hosted"},"recurringDays":[7],"startDate":"2023-01-01T21:00:00.000Z","timeZoneOffset":"+01:00"}],"type":"rpc","tid":113}'

  if [[ $OPTION_CREATE == 'true' ]]
  then
    for i in "bck" "docker" "npm" "browse" "search"
    do
      $CURL -X 'POST'  ${BASE_URL}'/service/extdirect' \
          -H 'Content-Type: application/json' \
          --data-raw "${!i}" > /dev/null
    done
    echo $BLOB | jq -c '.[]' | while read i; do
      blob_mane=$(echo $i | jq -r .name)
      resu=$(echo $cpt | jq -c ".data[].name = \"compact-blob-$blob_mane\" | .data[].properties.blobstoreName = \"$blob_mane\"")
      $CURL -X 'POST'  ${BASE_URL}'/service/extdirect' \
          -H 'Content-Type: application/json' \
          --data-raw "$resu" > /dev/null
    done
    for i in $YUM_REPOS_NAME
    do
      resu=$(echo $yum | jq -c ".data[].name = \"repair-rebuild-yum-metadata-$i\" | .data[].properties.repositoryName = \"$i\"")
      $CURL -X 'POST'  ${BASE_URL}'/service/extdirect' \
          -H 'Content-Type: application/json' \
          --data-raw "$resu" > /dev/null
    done
  fi
  if [[ $OPTION_LIST == 'true' ]]
  then
    while :
    do
      resu=$($CURL -X 'GET' \
            ${BASE_URL}'/service/rest/v1/tasks' \
            -H 'accept: application/json')
      continuationToken=$(echo $resu | jq -r .continuationToken)
      echo $resu | jq -c '.items[]' | while read i; do
        echo $i | jq -r '. | "\(.id)\t\t\(.name)\t\t\(.type) "'
      done
      [ "$continuationToken" == "null" ] && break
    done
  fi
  if [[ $OPTION_REMOVE_ALL == 'true' ]]
  then
    while :
    do
      resu=$($CURL -X 'GET' \
            ${BASE_URL}'/service/rest/v1/tasks' \
            -H 'accept: application/json')
      continuationToken=$(echo $resu | jq -r .continuationToken)
      echo $resu | jq -c '.items[]' | while read i; do
        id=$(echo $i | jq -r '.id')
        $CURL -X 'POST'  ${BASE_URL}'/service/extdirect' \
            -H 'Content-Type: application/json' \
            --data-raw "{\"action\":\"coreui_Task\",\"method\":\"remove\",\"data\":[\"$id\"],\"type\":\"rpc\",\"tid\":402}" > /dev/null
      done
      [ "$continuationToken" == "null" ] && break
    done
  fi
}

parse_args "$@"
case "$CMD" in
  "LIST")
    ping
    list
    ;;
  "BACKUP_CFG")
    ping
    "backup_config"
    ;;
  "BACKUP")
    ping
    backup 
    compress
    ;;
  "RESTORE")
    ping
    restore
    ;;
  "RESTORE_CFG")
    ping
    restore_config
    ;;
  "DELETE")
    ping
    delete
    ;;
  "CACHE")
    ping
    invalidateCache
    ;;
  "TASK")
    ping
    task
    ;;
  "METADATA")
    ping
    getAllpage $ARGS_LIST 0 1
    ;;
  *) 
    exit 1
    ;;
esac
LL=$(cat $LOGERROR)
[ ! -z "$LL" ] && echo "${YELLOW}Warning${_RESET}: Can not download some files :" && cat "$LOGERROR" && exit 1
exit 0
