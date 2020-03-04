output "kubeconfig-admin" {
  value = module.bootstrap.kubeconfig-admin
}

output "worker_iam_instance_profile_arn" {
  value = aws_iam_instance_profile.worker_node.arn
}

# Outputs for Kubernetes Ingress

output "ingress_dns_name" {
  value       = aws_lb.nlb.dns_name
  description = "DNS name of the network load balancer for distributing traffic to Ingress controllers"
}

output "ingress_zone_id" {
  value       = aws_lb.nlb.zone_id
  description = "Route53 zone id of the network load balancer DNS name that can be used in Route53 alias records"
}

# Outputs for worker pools

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC for creating worker instances"
}

output "subnet_ids" {
  value       = module.vpc.private_subnets
  description = "List of subnet IDs for creating worker instances"
}

output "worker_security_groups" {
  value       = [aws_security_group.worker.id]
  description = "List of worker security group IDs"
}

output "controller_security_groups" {
  value       = [aws_security_group.controller.id]
  description = "List of controller security group IDs"
}

output "kubeconfig" {
  value = module.bootstrap.kubeconfig-kubelet
}

output "service_cidr" {
  value = local.service_cidr
}

# Outputs for custom load balancing

output "nlb_id" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.nlb.id
}
