# logs - 执行日志

按日期组织的命令执行输出。

## 目录结构

```
logs/
├── README.md
├── YYYY-MM-DD/
│   ├── <command>-<timestamp>.log
│   └── ...
```

## 当前日志

| 日期 | 内容 |
|---|---|

## 命名约定

`<command>-<timestamp>.log`

例：
- `charge-mode-conservation.log` - `sudo ./charge-mode conservation` 的输出
- `ec-diag-180845/` - ec-diag.sh 跑出的目录（脚本自带时间戳）

## 保留策略

- **保留期 6 个月**（用于"设备行为突变"对比回看）
- 关键发现已写进 `docs/<feature>.md` 的，老 log 可手动清
- 每半年跑一次清理（复制到终端执行）：

```bash
# 删除 6 个月以前的 logs/<日期>/ 目录
find /path/to/repo/logs/ \
     -maxdepth 1 -type d -name "20??-??-??" -mtime +180 -exec rm -rf {} +
```
