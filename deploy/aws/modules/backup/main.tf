data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_backup_vault" "this" {
  name = "${var.name}-vault"
  tags = var.tags
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "this" {
  name = var.name

  rule {
    rule_name         = "bounded-daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 18 * * ? *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.retention_days
    }
  }
}

resource "aws_backup_selection" "database" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.name}-database"
  plan_id      = aws_backup_plan.this.id
  resources    = [var.database_cluster_arn]
}
