# Create the specific IAM user for Elastic
resource "aws_iam_user" "elastic_monitor" {
  name = "elastic-rds-monitor"
  path = "/"
}

# Generate the credentials (Access Key and Secret Key)
resource "aws_iam_access_key" "elastic_monitor_keys" {
  user = aws_iam_user.elastic_monitor.name
}

# Grant permission to read CloudWatch metrics
resource "aws_iam_user_policy_attachment" "cloudwatch_ro" {
  user       = aws_iam_user.elastic_monitor.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Grant permission to read the RDS status
resource "aws_iam_user_policy_attachment" "rds_ro" {
  user       = aws_iam_user.elastic_monitor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess"
}

