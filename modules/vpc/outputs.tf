# Values other stacks and modules need: EKS takes the private subnets,
# RDS takes the database subnets, load balancers use the public subnets.

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC, for security group rules"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ (load balancers, NAT)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ (EKS nodes and pods)"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "Database subnet IDs, one per AZ (RDS only, no internet route)"
  value       = aws_subnet.database[*].id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs (one in dev, one per AZ in prod)"
  value       = aws_nat_gateway.this[*].id
}
