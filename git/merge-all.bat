git checkout dev
git pull origin dev

git checkout test
git pull origin test
git merge dev --no-edit
git push origin test

git checkout prod
git pull origin prod
git merge test --no-edit
git push origin prod

git checkout dev
