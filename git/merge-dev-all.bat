git checkout dev
git push origin dev

git checkout test
git merge dev
git push origin test

git checkout prod
git merge test
git push origin prod

git checkout dev
