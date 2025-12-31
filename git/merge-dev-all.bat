git checkout dev
git pull origin dev
git push origin dev

git checkout test
git pull origin test
git merge dev
git push origin test

git checkout prod
git pull origin prod
git merge test
git push origin prod

git checkout dev
