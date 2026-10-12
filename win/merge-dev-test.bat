git checkout dev
git pull origin dev

git checkout test
git pull origin test
git merge dev --no-edit
git push origin test

git checkout dev
