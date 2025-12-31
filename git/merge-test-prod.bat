git checkout test
git pull origin test
git push origin test

git checkout prod
git pull origin prod
git merge test
git push origin prod

git checkout test
