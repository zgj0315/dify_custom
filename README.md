# Dify 定制开发
```
# 关联官方仓库作为上游 (upstream) 
git remote add upstream https://github.com/langgenius/dify.git

# 获取官方所有代码和 Tag 
git fetch upstream --tags

# 基于官方 tag 1.13.3，创建并切换到 upstream_base
git checkout -b upstream_base_1.13.3 1.13.3

# 将 upstream_base_1.13.3 推到自己仓库
git push origin upstream_base_1.13.3

# 创建第一个版本分支，进行定制化开发
git checkout -b rel_v0.1.0 upstream_base_1.13.3

# 准备升级官方新版本，使用一个新分支 rel_v0.2.0
git checkout rel_v0.1.0
git checkout -b rel_v0.2.0
git fetch upstream --tags
git merge 1.13.2
```
