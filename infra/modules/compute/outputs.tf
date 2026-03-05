output "region" {
  value = var.region
}

output "api_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
