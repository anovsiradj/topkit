git checkout test
git pull origin test

git checkout prod
git pull origin prod
git merge test --no-edit
git push origin prod

git checkout test
