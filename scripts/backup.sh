---

# scripts/backup.sh
#!/bin/bash

# 数据库备份脚本
set -e

# 配置
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-notes_user}
DB_PASSWORD=${DB_PASSWORD:-notes_password}
DB_NAME=${DB_NAME:-notes_db}
BACKUP_DIR=${BACKUP_DIR:-./backup}
KEEP_DAYS=${BACKUP_KEEP_DAYS:-30}

# 创建备份目录
mkdir -p $BACKUP_DIR

# 生成备份文件名
BACKUP_FILE="$BACKUP_DIR/notes_$(date +%Y%m%d_%H%M%S).sql"

echo "开始备份数据库..."

# 执行备份
PGPASSWORD=$DB_PASSWORD pg_dump \
  -h $DB_HOST \
  -p $DB_PORT \
  -U $DB_USER \
  -d $DB_NAME \
  --no-password \
  --verbose \
  --clean \
  --no-owner \
  --no-privileges \
  > $BACKUP_FILE

# 压缩备份文件
gzip $BACKUP_FILE

echo "备份完成: ${BACKUP_FILE}.gz"

# 清理过期备份
find $BACKUP_DIR -name "notes_*.sql.gz" -type f -mtime +$KEEP_DAYS -delete

echo "已清理 $KEEP_DAYS 天前的备份文件"

---

