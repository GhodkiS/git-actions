#!/bin/bash

if [[ "$1" == "validate-environment" ]]; then
if [[ "$comment_body" == ".deploy"* ]]; then
t_env_app=$(echo "$comment_body" | sed 's/\.deploy //g')
elif [[ "$comment_body" == ".unlock"* ]]; then
t_env_app=$(echo "$comment_body" | sed 's/\.unlock //g')
elif [[ "$comment_body" == ".lock"* ]]; then
t_env_app=$(echo "$comment_body" | sed 's/\.lock //g'| sed 's/ --info//g' )
echo "in if loop"
echo "comment body: $comment_body"
fi
t_app=$(echo "$t_env_app" | awk -F '_' '{print $1}')
t_env=$(echo "$t_env_app" | awk -F '_' '{print $2}')
if [ ! -f "./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml" ]
then
echo "no $t_env_app target  environment found"
exit 1
fi
echo "GITHUB_TARGET_ENV=$t_env_app" >> $GITHUB_OUTPUT



elif [[ "$1" == "update-target-revision" ]]; then
t_env_app="$2"
t_app=$(echo "$t_env_app" | awk -F '_' '{print $1}')
t_env=$(echo "$t_env_app" | awk -F '_' '{print $2}')
file="./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml"
sed -i '/# lock target environment starts/,/# lock target environment ends/d' $file
multiline_text=$(cat <<EOF
# lock target environment starts
- target:
    kind: Application
    name: $t_app
patch: |-
    - op: replace
        path: /spec/source/targetRevision
        value: $3
# lock target environment ends
EOF
)
echo "$multiline_text" >> "$file"
git config --global user.name 'test-user'
git config --global user.email 'saurabh.ghodki91@gmail.com'
if [[ -n $(git status --porcelain) ]]; then
git add ./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml
git commit -am "update target revision of $2 to $3 [skip ci]"
git push
fi


elif [[ "$1" == "update-lock-json" ]]; then
json_file="lock.json"
key_to_update1="branch"
key_to_update2="link"
new_value1=$3
new_value2=$2
json_content=$(cat "$json_file")
updated_json=$(echo "$json_content" | jq --arg key "$key_to_update1" --arg value "$new_value1" '.[$key] = $value')
echo "$updated_json" > "$json_file"
json_content=$(cat "$json_file")
updated_json=$(echo "$json_content" | jq --arg key "$key_to_update2" --arg value "$new_value2" '.[$key] = $value')
echo "$updated_json" > "$json_file"
git config --global user.name 'test-user'
git config --global user.email 'tech.user@company.com'
git add "$json_file"
git commit -am "update branch target [skip ci]"
git push


elif [[ "$1" == "unlock-action" ]]; then
t_app=$(echo "$t_env_app" | awk -F '_' '{print $1}')
t_env=$(echo "$t_env_app" | awk -F '_' '{print $2}')
file="./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml"
sed -i '/# lock target environment starts/,/# lock target environment ends/d' $file
git config --global user.name 'test-user'
git config --global user.email 'saurabh.ghodki91@gmail.com'
if [[ -n $(git status --porcelain) ]]; then
git add ./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml
git commit -am "unlock $t_env_app [skip ci]"
git push
fi


elif [ "$1" == "search-locks" ]; then
json_file="lock.json"
key_to_update="branch"
for branch in $(git branch -r | grep "\-branch\-deploy\-lock");
do
git checkout $branch
lock_branch=$(jq -r ".branch" "$json_file" 2> /dev/null)
lock_env=$(jq -r ".environment" "$json_file" 2> /dev/null)
if [[ "$lock_branch" == "$2" ]]
then
git_active_lock_flag=true
git_active_lock="${git_active_lock},${lock_env}"
fi
done
if [[ "${git_active_lock_flag}" = true ]]
then
git_active_lock=$(echo $git_active_lock | cut -c2-)
echo "found active locks: ${git_active_lock}"
echo "GITHUB_ACTIVE_LOCKS=$git_active_lock" >> $GITHUB_OUTPUT
fi
git checkout main


elif [[ "$1" == "unlock-pr-close" ]]; then
git config --global user.name 'test-user'
git config --global user.email 'saurabh.ghodki91@gmail.com'
active_locks="$2"
for t_branches in $(echo $active_locks | sed "s/,/ /g")
do
git push origin --delete "${t_branches}-branch-deploy-lock"
done


elif [[ "$1" == "commit-unlock-main" ]]; then
git config --global user.name 'test-user'
git config --global user.email 'saurabh.ghodki91@gmail.com'
active_locks="$2"
for t_env_app in $(echo $active_locks | sed "s/,/ /g")
do
t_app=$(echo "$t_env_app" | awk -F '_' '{print $1}')
t_env=$(echo "$t_env_app" | awk -F '_' '{print $2}')
file="./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml"
sed -i '/# lock target environment starts/,/# lock target environment ends/d' $file
git add ./argocd/overlays/$t_env/applications/$t_app/kustomization.yaml
done
git commit -am "unlock $t_env_app [skip ci]"
git push
fi