output "webserver_public_ip" {
  value = aws_instance.wordpress-server.public_ip
}

output "webserver_private_ip" {
  value = aws_instance.wordpress-server.private_ip
}


output "bastion_public_ip" {
  value = aws_instance.bastion-server.public_ip
}


output "bastion_private_ip" {
  value = aws_instance.bastion-server.private_ip
}
