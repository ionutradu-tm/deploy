#!/bin/bash

#VARS:

REPO_USER=$WERCKER_DEPLOY_REPO_USER
REPO_NAME=$WERCKER_DEPLOY_REPO_NAME
REPO_PATH=$WERCKER_CACHE_DIR"/my_tmp/"$REPO_NAME
SOURCE_BRANCH=$WERCKER_DEPLOY_SOURCE_BRANCH
TO_BRANCH=$WERCKER_DEPLOY_TO_BRANCH
FORCE_BUILD_NUMBER=$WERCKER_DEPLOY_FORCE_BUILD_NUMBER
BUILD_TAG=$WERCKER_DEPLOY_BUILD_TAG
FORCE_CLONE=$WERCKER_DEPLOY_FORCE_CLONE
TAG_PROD=$WERCKER_DEPLOY_TAG_PROD
TAG_PATH=$WERCKER_SOURCE_DIR"/tag"
#VARS




# clone or pull a repository
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: branch name
# ARG5: remove REPO_PATH
function clone_pull_repo (){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local BRANCH=$4
        local DEL_REPO_PATH=$5


        if [[ ${DEL_REPO_PATH,,} == "yes" ]];then
                rm -rf $REPO_PATH
        fi
        #check if REPO_PATH exists
        if [ ! -d "$REPO_PATH" ]; then
                echo "Clone repository: $REPO"
                mkdir -p $REPO_PATH
                cd $REPO_PATH
                echo "git clone git@github.com:$USER/$REPO.git . >/dev/null"
                git clone git@github.com:$USER/$REPO.git . >/dev/null
                if [ $? -eq 0 ]; then
                        echo "Repository $REPO created"
                else
                        echo "Failed to create repository $REPO"
                        rm -rf $REPO_PATH
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
        git remote prune origin | awk 'BEGIN{FS="origin/"};/pruned/{print $3}' | xargs -r git branch -D
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
# ARG3: branch name
#
function switch_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local BRANCH=$3

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

        switch_branch $REPO $REPO_PATH $FROM_BRANCH
        LATEST_BUILD_NUMBER=$(git tag -l $TAG_PREFIX\+* | cut -d\+ -f2| sort -rn|  head -n 1)
        if [[ -z $LATEST_BUILD_NUMBER ]];then
                LATEST_TAG=""
                COMMIT_WITH_LATEST_TAG=""
        else
                LATEST_TAG=$TAG_PREFIX"+"$LATEST_BUILD_NUMBER
                echo "LATEST_TAG: $LATEST_TAG"
                COMMIT_WITH_LATEST_TAG=$(git rev-list -1 $LATEST_TAG)
                echo "commit with latest tag: $COMMIT_WITH_LATEST_TAG"
                LAST_COMMIT_SHA=$(git rev-parse $FROM_BRANCH)
                echo "LAST_COMMIT_SHA: $LAST_COMMIT_SHA"
                if [[ "$LAST_COMMIT_SHA" == "$COMMIT_WITH_LATEST_TAG" ]];then
                        echo "No need to increase the build number"
                        INCREASE_BUILD_NUMBER="FALSE"
                        export VERSION_TAG=$LATEST_TAG
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

        LAST_SHA=$(git rev-parse $FROM_BRANCH)
        git branch --contains $LAST_SHA | grep -w $TO_BRANCH
        if [ $? -eq 0 ]; then
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
        echo "switch_branch $REPO $REPO_PATH $FROM_BRANCH"
        switch_branch $REPO $REPO_PATH $FROM_BRANCH
        echo "git checkout -b $NEW_BRANCH $FROM_BRANCH"
        git checkout -b $NEW_BRANCH $FROM_BRANCH
        if [ $? -eq 0 ]; then
                echo "Succesfully created branch $NEW_BRANCH"
                git commit --allow-empty -m "Deploy $FROM_BRANCH to $NEW_BRANCH"
                git push -f origin $NEW_BRANCH
                if [ $? -eq 0 ]; then
                        echo "Succesfully pushed branch $NEW_BRANCH"
                else
                        echo "Error while pushing bracnh $NEW_BRANCH"
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
                echo "git tag $NEW_TAG $COMMIT_SHA"
                git push origin $NEW_TAG
                echo "git push origin $NEW_TAG"

        else
                echo "Please clone repository $REPO first"
                return 2
        fi

}



# Delete a branch (local)
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: branch
#
function delete_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local BRANCH=$3

        git branch -D $BRANCH

}
#end functions
#############################################################3

#set git
git config --global user.email email@wercker.com
git config --global user.name wercker
git config --global push.default simple
#end set git

#check vars

if [[ -z $REPO_USER ]]; then
    echo "Please provide repo username"
    exit 1
fi
if [[ -z $REPO_NAME ]]; then
    echo "Please provide repo name"
    exit 1
fi
if [[ -z $SOURCE_BRANCH ]]; then
    echo "Please provide source branch"
    exit 1
fi
if [[ -z $TO_BRANCH ]]; then
    echo "Please provide destination branch"
    exit 1
fi

#end check


mkdir -p $TAG_PATH

if [[ -n $DEPLOY_BUILD_TAG ]]; then
        echo "Deploy from build number"
        #clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER master
        #TAG_FOUND=$(git tag -l $TAG |wc -l)
        #if [[ $TAG_FOUND == "0" ]]; then
        #    echo "TAG $DEPLOY_BUILD_TAG not found"
        #    exit 3
        #fi
        #export $SOURCE_BRANCH=$DEPLOY_BUILD_TAG
        exit 0
else
    echo "clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH $FORCE_CLONE"
    clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH $FORCE_CLONE
    if [ $? -ne 0 ]; then
        echo "Branch $SOURCE_BRANCH not found"
        exit 3
    fi
fi

# check if the destination branch exists"
echo "clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER $TO_BRANCH"
clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER $TO_BRANCH
if [ $? -eq 0 ]; then
        #destination branch exists
        echo "compare_branches $REPO_NAME $REPO_PATH $SOURCE_BRANCH $TO_BRANCH"
        #compare_branches $REPO_NAME $REPO_PATH $SOURCE_BRANCH $TO_BRANCH
        echo "switch_branch $REPO_NAME $REPO_PATH $SOURCE_BRANCH"
        switch_branch $REPO_NAME $REPO_PATH $SOURCE_BRANCH
        echo "delete_branch $REPO_NAME $REPO_PATH $TO_BRANCH"
        delete_branch $REPO_NAME $REPO_PATH $TO_BRANCH
fi

export ENVIRONMENT=$TO_BRANCH

echo "clone_branch $REPO_NAME $REPO_PATH $SOURCE_BRANCH $TO_BRANCH"
clone_branch $REPO_NAME $REPO_PATH $SOURCE_BRANCH $TO_BRANCH
echo "$SOURCE_BRANCH cloned into $TO_BRANCH"
# get the latest build number
echo "get_build_number_commit_prefix_tag $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH"
get_build_number_commit_prefix_tag $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH
# check if we need to increment the build number
if [[ -z $INCREASE_BUILD_NUMBER ]]; then
        if [[ -n $LATEST_TAG ]]; then
                echo "Latest build: $LATEST_BUILD_NUMBER"
                NEW_BUILD_NUMBER=$((LATEST_BUILD_NUMBER + 1))
                echo "NEW build: $NEW_BUILD_NUMBER"
                export NEW_TAG=$SOURCE_BRANCH"+"$NEW_BUILD_NUMBER
                export OLD_TAG=$SOURCE_BRANCH"+"$LATEST_BUILD_NUMBER
                export VERSION_TAG=$NEW_TAG
                #echo $OLD_TAG > $REPO_PATH_TAG/old_tag.txt
                #echo $NEW_TAG > $REPO_PATH_TAG/new_tag.txt
        fi
fi

# check if the build number is forced
if [[ -n $FORCE_BUILD_NUMBER ]]; then
        # force a build tag
        FORCE_BUILD_TAG=$SOURCE_BRANCH"+"$FORCE_BUILD_NUMBER
        echo "tag_commit_sha $REPO_NAME $REPO_PATH $REPO_USER $FORCE_BUILD_TAG"
        tag_commit_sha $REPO_NAME $REPO_PATH $REPO_USER $FORCE_BUILD_TAG
        export NEW_TAG=$FORCE_BUILD_TAG
        export VERSION_TAG=$NEW_TAG
        #echo  $FORCE_BUILD_NUMBER > $REPO_PATH_TAG/new_tag.txt
else
        if [[ -n $NEW_TAG ]]; then
                echo "tag_commit_sha $REPO_NAME $REPO_PATH $REPO_USER $NEW_TAG $COMMIT_WITH_LATEST_TAG"
                tag_commit_sha $REPO_NAME $REPO_PATH $REPO_USER $NEW_TAG $LAST_COMMIT_SHA
        fi
fi
