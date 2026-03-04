# merchant_web

使用方法

更新到 最新包（默认）：

bash merchant_web_update.sh

更新到 指定包：

bash merchant_web_update.sh --pkg merchant_web_20260304_171838.tar.gz

回滚到最近备份：

bash merchant_web_update.sh rollback

回滚到指定备份：

bash merchant_web_update.sh rollback-to merchant_web_20260304_155000.tar.gz


# merchant

bash merchant_update.sh → 当前目录下 merchant 或 merchant*.tar.gz

bash merchant_update.sh --pkg ./merchant_20260304_174500.tar.gz → 指定包更新

bash merchant_update.sh rollback → 回滚上一个版本

bash merchant_update.sh rollback merchant.bak.20260304-174500.tar.gz → 回滚指定备份