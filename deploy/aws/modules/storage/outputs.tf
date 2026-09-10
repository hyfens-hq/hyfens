output "bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}

output "bucket_regional_domain_name" {
  value = aws_s3_bucket.artifacts.bucket_regional_domain_name
}
