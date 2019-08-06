#!/bin/bash

#VARS:

REPO_USER=$WERCKER_DEPLOY_REPO_USER
REPO_NAME=$WERCKER_DEPLOY_REPO_NAME
REPO_PATH=$$WERCKER_CACHE_DIR$REPO_NAME
SOURCE_BRANCH=$WERCKER_DEPLOY_SOURCE_BRANCH
TO_BRANCH=$WERCKER_DEPLOY_TO_BRANCH
FORCE_BUILD_NUMBER=$WERCKER_DEPLOY_FORCE_BUILD_NUMBER
BUILD_NUMBER=$WERCKER_DEPLOY_BUILD_NUMBER

# clone or pull a repository
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: branch name
function clone_pull_repo (){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local BRANCH=$4

        #check if REPO_PATH exists
        if [ ! -d "$REPO_PATH" ]; then
                echo "Clone repository: $REPO"
                mkdir -p $REPO_PATH
                cd $REPO_PATH
                git clone git@github.com:$USER/$REPO.git . >/dev/null
                if [ $? -eq 0 ]; then
                        echo "Repository $REPO created"
                else
                        echo "Failed to create repository $REPO"
                        return 3
                fi
        fi
        echo "Pull repository: $REPO"
        cd $REPO_PATH
        git checkout $BRANCH
        if [ $? -eq 0 ]; then
                echo "Succesfully switched to branch $BRANCH"
                git pull 2>/dev/null
        else
                echo "Branch $BRANCH does not exists"
                return 3
        fi
        # prunes tracking branches not on the remote
        git remote prune origin
        if [ $? -eq 0 ]; then
                echo "Repository $REPO pruned"
        else
                echo "Failed to prune repository $REPO"
                return 2
        fi
}

# Switch to a specific branch
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: branch name
#
function switch_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local BRANCH=$4

        #check if REPO_PATH exists
        if [ -d "$REPO_PATH" ]; then
                echo "Switch to branch $BRANCH "
                cd $REPO_PATH
                #git pull >/dev/null
                git checkout $BRANCH >/dev/null
                if [ $? -eq 0 ]; then
                        echo "Succesfully switched to branch $BRANCH"
                else
                        echo "Branch $BRANCH does not exists"
                        return 3
                fi
        else
                echo "Please clone repository $REPO first"
                return 2
        fi


}

# Get the latest build number and the latest commit
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: tag prefix (branch_name)
# return COMMIT_WITH_LATEST_TAG, LATEST_TAG (empty if the tag not found) and INCREASE_BUILD_NUMBER (do we need to increment BUILD_NUMBER)
function get_build_number_commit_prefix_tag(){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local TAG_PREFIX=$4
        local FROM_BRANCH=$4

        echo "Tag Prefix: $TAG_PREFIX"

        switch_branch $REPO $REPO_PATH $USER $FROM_BRANCH
        LATEST_BUILD_NUMBER=$(git tag -l $TAG_PREFIX\+* | cut -d\+ -f2| sort -rn|  head -n 1)
        if [[ -z $LATEST_BUILD_NUMBER ]];then
                LATEST_TAG=""
                COMMIT_WITH_LATEST_TAG=""
        else
                LATEST_TAG=$TAG_PREFIX"+"$LATEST_BUILD_NUMBER
                COMMIT_WITH_LATEST_TAG=$(git rev-list -1 $LATEST_TAG)
                echo "commit with latest tag: $COMMIT_WITH_LATEST_TAG"
                LAST_COMMIT_SHA=$(git log -n 1 |  head -n 1 |  cut -d\  -f2)
                if [[ "$LAST_COMMIT_SHA" == "$COMMIT_WITH_LATEST_TAG" ]];then
                        echo "No need to increase the build number"
                        INCREASE_BUILD_NUMBER="FALSE"
                fi
        fi

}

# Compare two branches
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: from branch
# ARG4: to branch
#
function compare_branches(){
        local REPO=$1
        local REPO_PATH=$2
        local FROM_BRANCH=$3
        local TO_BRANCH=$4

        if [[ $(git rev-parse $FROM_BRANCH) = $(git rev-parse $TO_BRANCH) ]]; then
                echo "$FROM_BRANCH and $TO_BRANCH are the same"
                exit 3
        fi

}


# Clone a branch from a specific branch
# Add a commit message
# push the new branch to the repository
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: source branch
# ARG4: to  branch
#
function clone_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local FROM_BRANCH=$3
        local NEW_BRANCH=$4

        # switch to the soruce branch and update it
        switch_branch $REPO $REPO_PATH $USER $FROM_BRANCH
        git checkout -b $NEW_BRANCH $FROM_BRANCH
        if [ $? -eq 0 ]; then
                echo "Succesfully created branch $NEW_BRANCH"
                git commit --allow-empty -m "Deploy $FROM_BRANCH to $NEW_BRANCH"
                git push -f origin $NEW_BRANCH
                if [ $? -eq 0 ]; then
                        echo "Succesfully pushed branch $NEW_BRANCH"
                else
                        echo "Error during while pushing bracnh $NEW_BRANCH"
                        exit 2
                fi
        else
                echo "Errors during creating new branch $NEW_BRANCH"
                exit 3
        fi
}

# Tag commit. If the commit is not provided the last commit will be tagged
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: TAG
# ARG5: commit sha (if the commit sha is missing the last commit will be tagged)
#
function tag_commit_sha(){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local NEW_TAG=$4
        local COMMIT_SHA=$5

        if [ -d "$REPO_PATH" ]; then
                if [[ -z $COMMIT_SHA ]]; then
                        COMMIT_SHA=$(git log -n 1 |  head -n 1 |  cut -d\  -f2)
                fi
                git tag $NEW_TAG $COMMIT_SHA
                #git push origin $tag

        else
                echo "Please clone repository $REPO first"
                return 2
        fi

}

#end functions
#############################################################3

if [[ -n $DEPLOY_BUILD_NUMBER ]]; then
        echo "Deploy from build number"
fi
clone_pull_repo $REPO $REPO_PATH $REPO_USER $SOURCE_BRANCH
if [ $? -ne 0 ]; then
        echo "Branch $SOURCE_BRANCH does not exists"
        exit 3
fi
# check if the destination branch exists"
clone_pull_repo $REPO $REPO_PATH $REPO_USER $TO_BRANCH
if [ $? -eq 0 ]; then
        #destination branch exists
        compare_branches $REPO $REPO_PATH $SOURCE_BRANCH $TO_BRANCH
        switch_branch $REPO $REPO_PATH $REPO_USER $SOURCE_BRANCH
        delete_branch $REPO $REPO_PATH $TO_BRANCH
fi
echo "clone_branch $REPO $REPO_PATH $SOURCE_BRANCH $TO_BRANCH"
clone_branch $REPO $REPO_PATH $SOURCE_BRANCH $TO_BRANCH
echo "$SOURCE_BRANCH cloned into $TO_BRANCH"
# get the latest build number
echo "get_build_number_commit_prefix_tag $REPO $REPO_PATH $REPO_USER $SOURCE_BRANCH"
get_build_number_commit_prefix_tag $REPO $REPO_PATH $REPO_USER $SOURCE_BRANCH
# check if we need to increment the build number
if [[ -z $INCREASE_BUILD_NUMBER ]]; then
        if [[ -n $LATEST_TAG ]]; then
                echo "Latest build: $LATEST_BUILD_NUMBER"
                NEW_BUILD_NUMBER=$((LATEST_BUILD_NUMBER + 1))
                echo "NEW build: $NEW_BUILD_NUMBER"
                NEW_TAG=$SOURCE_BRANCH"+"$NEW_BUILD_NUMBER
                OLD_TAG=$SOURCE_BRANCH"+"$LATEST_BUILD_NUMBER
                #echo $OLD_TAG > $REPO_PATH_TAG/old_tag.txt
                #echo $NEW_TAG > $REPO_PATH_TAG/new_tag.txt
        fi
fi

# check if the build number is forced
if [[ -n $FORCE_BUILD_NUMBER ]]; then
        # force a build number
        echo "tag_commit_sha $REPO $REPO_PATH $REPO_USER $FORCE_BUILD_NUMBER"
        tag_commit_sha $REPO $REPO_PATH $REPO_USER $FORCE_BUILD_NUMBER
        #echo  $FORCE_BUILD_NUMBER > $REPO_PATH_TAG/new_tag.txt
else
        if [[ -n $NEW_TAG ]]; then
                echo "tag_commit_sha $REPO $REPO_PATH $REPO_USER $NEW_TAG $COMMIT_WITH_LATEST_TAG"
                tag_commit_sha $REPO $REPO_PATH $REPO_USER $NEW_TAG $LAST_COMMIT_SHA
        fi
fi