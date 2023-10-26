#!/bin/bash

usage() {
  echo "Usage:"
  echo "  $SCRIPT_NAME [ -a ACTION ]"
  echo
  echo "  -h - It shows this help"
  echo
  echo "  -a - Required option. The action to run the script with. E.g.: validate-environment"
}

exit_with_error() {
  usage
  exit 1
}

# set variables
SCRIPT_NAME=$(basename "$0")

## get parameters / options
while getopts ":h:a:" opt;
do
  case ${opt} in
    h )
      echo
      usage
      exit 0
      ;;
    a )
      if [ -z "$OPTARG" ] || [ "${OPTARG:0:1}" = "-" ]
      then
        echo "Error: -a requires an argument"
        exit 1
      fi
      ACTION=$OPTARG
      ;;
    \? )
      echo "Invalid Option: -$OPTARG" 1>&2
      exit_with_error
      ;;
    : )
      echo "Invalid Option: -$OPTARG requires an argument" 1>&2
      exit_with_error
      ;;
  esac
done

## error handling

if [ -z "$ACTION" ]
then
  echo "-a parameter not set"
  exit_with_error
fi

#===============================================================================================
# Functions

validate-environment() {
if [[ "$COMMENT_BODY" == ".deploy"* ]]; then
t_env_app="${COMMENT_BODY//.deploy /}"
elif [[ "$COMMENT_BODY" == ".unlock"* ]]; then
t_env_app="${COMMENT_BODY//.unlock /}"
elif [[ "$COMMENT_BODY" == ".lock"* ]]; then
t_env_app_temp="${COMMENT_BODY//.lock /}"
t_env_app="${t_env_app_temp/ --info/}"
echo "in if loop"
echo "comment body: $COMMENT_BODY"
fi
t_app=$(echo "$t_env_app" | awk -F '_' '{print $1}')
t_env=$(echo "$t_env_app" | awk -F '_' '{print $2}')
if [ ! -f "./$t_env/applications/$t_app/kustomization.yaml" ]
then
echo "no $t_env_app target  environment found"
exit 1
fi
echo "GITHUB_TARGET_ENV=$t_env_app" >> "${GITHUB_OUTPUT}"
}


update-target-revision() {
t_app=$(echo "$T_ENV_APP" | awk -F '_' '{print $1}')
t_env=$(echo "$T_ENV_APP" | awk -F '_' '{print $2}')
file="./$t_env/applications/$t_app/kustomization.yaml"
sed -i '/# lock target environment starts/,/# lock target environment ends/d' "$file"
multiline_text=$(cat <<EOF
# lock target environment starts
- target:
    kind: Application
    name: $t_app
  patch: |-
    - op: replace
        path: /spec/source/targetRevision
        value: $T_BRANCH
# lock target environment ends
EOF
)
tail_s=$(tail -c 1 "${file}")
if [[ -n "$tail_s" ]]; then
    echo -e "\n$multiline_text" >> "${file}"
else
    echo -e "$multiline_text" >> "${file}"
fi
}

cleanup() {
git push origin --delete "${T_ENV_APP}-merge-temp"
}

update-lock-json() {
json_file="lock.json"
key_to_update1="branch"
key_to_update2="link"
new_value1=$T_BRANCH
new_value2=$COMMENT_URL
json_content=$(cat "$json_file")
updated_json=$(echo "$json_content" | jq --arg key "$key_to_update1" --arg value "$new_value1" '.[$key] = $value')
echo "$updated_json" > "$json_file"
json_content=$(cat "$json_file")
updated_json=$(echo "$json_content" | jq --arg key "$key_to_update2" --arg value "$new_value2" '.[$key] = $value')
echo "$updated_json" > "$json_file"
git add "$json_file"
git commit -am "update branch target [skip ci]"
git push
}

unlock-action() {
t_app=$(echo "$T_ENV_APP" | awk -F '_' '{print $1}')
t_env=$(echo "$T_ENV_APP" | awk -F '_' '{print $2}')
file="./$t_env/applications/$t_app/kustomization.yaml"
sed -i '/# lock target environment starts/,/# lock target environment ends/d' "${file}"
}

search-locks() {
json_file="lock.json"
for branch in $(git branch -r | grep "\-branch\-deploy\-lock");
do
git checkout "${branch}"
lock_branch=$(jq -r ".branch" "$json_file" 2> /dev/null)
lock_env=$(jq -r ".environment" "$json_file" 2> /dev/null)
if [[ "$lock_branch" == "$T_BRANCH" ]]
then
git_active_lock_flag=true
git_active_lock="${git_active_lock},${lock_env}"
fi
done
if [[ "${git_active_lock_flag}" = true ]]
then
git_active_first_lock=$(echo "${git_active_lock/,/}" | cut -d',' -f1)
echo "found active locks: ${git_active_lock/,/}"
echo "GITHUB_ACTIVE_LOCKS=${git_active_lock/,/}" >> "${GITHUB_OUTPUT}"
echo "GITHUB_ACTIVE_FIRST_LOCK=${git_active_first_lock/,/}" >> "${GITHUB_OUTPUT}"
fi
git checkout main
}

search-locks-app() {
json_file="lock.json"
branch=$(git branch -r | grep "\-branch\-deploy\-lock" | grep "$T_ENV")
if [[ -n "${branch}" ]]; then
github_lock_app="${GITHUB_LOCK_APPS},${T_ENV}"
echo "GITHUB_LOCK_APPS=${github_lock_app#,}" >> "${GITHUB_OUTPUT}"
fi
}

unlock-pr-close() {
for t_branches in ${ACTIVE_LOCKS//,/ }
do
git push origin --delete "${t_branches}-branch-deploy-lock"
done
}


commit-unlock-main() {
for t_env_app in ${ACTIVE_LOCKS//,/ }
do
t_app=$(echo "$t_env_app" | awk -F '_' '{print $1}')
t_env=$(echo "$t_env_app" | awk -F '_' '{print $2}')
file="./$t_env/applications/$t_app/kustomization.yaml"
sed -i '/# lock target environment starts/,/# lock target environment ends/d' "${file}"
done
}

gh-cli() {
type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
&& sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt update \
&& sudo apt install gh -y
}
#===============================================================================================
# MAIN

case $ACTION in
  validate-environment)
   validate-environment
   ;;
 update-lock-json)
   update-lock-json
   ;;
 update-target-revision)
   update-target-revision
   ;;
 unlock-action)
   unlock-action
   ;;
 search-locks)
   search-locks
   ;;
 search-locks-app)
   search-locks-app
   ;;
 unlock-pr-close)
   unlock-pr-close
   ;;
 commit-unlock-main)
   commit-unlock-main
   ;;
 cleanup)
   cleanup
   ;;
gh-cli)
   gh-cli
   ;;
 *)
   exit_with_error
   ;;
esac