#!/usr/bin/env bash

set -x

# Set variables
UPSTREAM_REPO=$1
UPSTREAM_BRANCH=$2
DOWNSTREAM_BRANCH=$3
GITHUB_TOKEN=$4
FETCH_ARGS=$5
MERGE_ARGS=$6
PUSH_ARGS=$7
SPAWN_LOGS=$8

if [[ -z "$UPSTREAM_REPO" ]]; then
  echo "Missing \$UPSTREAM_REPO"
  exit 1
fi

if [[ -z "$DOWNSTREAM_BRANCH" ]]; then
  echo "Missing \$DOWNSTREAM_BRANCH"
  echo "Default to ${UPSTREAM_BRANCH}"
  DOWNSTREAM_BREANCH=UPSTREAM_BRANCH
fi

if ! echo "$UPSTREAM_REPO" | grep '\.git'; then
  UPSTREAM_REPO="https://github.com/${UPSTREAM_REPO_PATH}.git"
fi

echo "UPSTREAM_REPO=$UPSTREAM_REPO"


# Checkout repository working and add upstream remote
git clone -b $DOWNSTREAM_BRANCH "https://github.com/${GITHUB_REPOSITORY}.git" work
cd work || { echo "Missing work dir" && exit 2 ; }

git config user.name "${GITHUB_ACTOR}"
git config user.email "${GITHUB_ACTOR}@users.noreply.github.com"
git config --local user.password ${GITHUB_TOKEN}

git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

git remote add upstream "$UPSTREAM_REPO"
git fetch ${FETCH_ARGS} upstream
git remote -v

git checkout ${DOWNSTREAM_BRANCH}


# Get percentage files modified
RST_FILES=$(find ./ -name "*.rst")
N_RST_FILES=$(find ./ -name "*.rst"|wc -l)

COUNT_DIFF=0
for i in $RST_FILES
do
  if [[ $(git --no-pager diff upstream/${UPSTREAM_BRANCH} -- $i) ]]
  then
    COUNT_DIFF=$((COUNT_DIFF + 1))
  fi
done

PERCENTAGE_DIFF_FILES=$(awk "BEGIN { print ${COUNT_DIFF} / ${N_RST_FILES} }")

# Merge and get files with conflict
MERGE_RESULT=$(git merge ${MERGE_ARGS} upstream/${UPSTREAM_BRANCH})
CONFLICTS=$(git ls-files -u  | awk '{print $4}' | sort | uniq)


if [[ $MERGE_RESULT == "" ]] 
then
  exit 1
elif [[ $MERGE_RESULT != *"Already up to date."* ]]
then
  git commit -m "Merged upstream"
  git push ${PUSH_ARGS} origin ${DOWNSTREAM_BRANCH} || exit $?
fi

cd ..
rm -rf work

echo "merge_result<<EOF" >> $GITHUB_OUTPUT
echo "${MERGE_RESULT}" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "conflicts<<EOF" >> $GITHUB_OUTPUT
echo "${CONFLICTS}" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "completed<<EOF" >> $GITHUB_OUTPUT
echo "${PERCENTAGE_DIFF_FILES}" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

if [[ $CONFLICTS ]]
then 
  echo "Please resolve conflicts in next files:" > bodyfile 
  echo "${CONFLICTS}" >> bodyfile 
  echo  >> bodyfile 
  echo "Complete message: " >> bodyfile 
  echo "${MERGE_RESULT}" >> bodyfile

  # if GH_TOKEN=${GITHUB_TOKEN} gh issue list --repo https://github.com/${GITHUB_REPOSITORY}.git | grep -v "Fix conflict in $CONFLICTS"
  # then 
    # gh auth login --git-protocol https --hostname GitHub.com --with-token < gt
    GH_TOKEN=${GITHUB_TOKEN} gh issue create --repo https://github.com/${GITHUB_REPOSITORY}.git --title "Fix conflict in $CONFLICTS" --body-file bodyfile
  # fi
fi
