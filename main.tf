
#Set up a new VPC
 resource "aws_vpc" "awslab-vpc" {                # Creating VPC here
   cidr_block       = "${var.awslab_vpc_cidr}"     # Defining the CIDR block 
   #instance_tenancy = "${var.region}"
   enable_dns_hostnames  = true
   tags = {
    Name = "CocusVPC"
  }
 }

#Configure and attach Internet gateway
resource "aws_internet_gateway" "IGW" {    # Creating Internet Gateway
    vpc_id =  aws_vpc.awslab-vpc.id              
 }
 
 # Creating Public Subnet
 resource "aws_subnet" "awslab-subnet-public" {    
   vpc_id =  aws_vpc.awslab-vpc.id
   cidr_block = "${var.public_subnets}"        # CIDR block of public subnets
   map_public_ip_on_launch="true"
 }
 # Creating Private Subnets
 resource "aws_subnet" "awslab-subnet-private" {
   vpc_id =  aws_vpc.awslab-vpc.id
   cidr_block = "${var.private_subnets}"          # CIDR block of private subnets
 }
 
#Creating a Routing table
resource "aws_route_table" "awslab-rt-internet" {
  vpc_id = aws_vpc.awslab-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
}


#Route table Association with Public Subnet
 resource "aws_route_table_association" "awslab-rt-internet-association" {
    subnet_id = aws_subnet.awslab-subnet-public.id
    route_table_id = aws_route_table.awslab-rt-internet.id
 }

 #Security Group for our DB(Private subnet) Instance
resource "aws_security_group" "database" {
  description = "DB Security Group"
  vpc_id      = aws_vpc.awslab-vpc.id

  ingress {
    from_port   = 0
    to_port     = -1
    protocol    = "ICMP"
    cidr_blocks = ["172.16.1.0/24"]
    security_groups=["${aws_security_group.webserver.id}"]
  }

  ingress {
    from_port   = 3110
    to_port     = 3110
    protocol    = "tcp"
    cidr_blocks = ["172.16.1.0/24"]
    security_groups=["${aws_security_group.webserver.id}"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.16.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

#Security Group for our Webserver Instance
resource "aws_security_group" "webserver" {
 
  vpc_id      = aws_vpc.awslab-vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "ICMP"
    from_port   = 0
    to_port     = -1
    protocol    = "ICMP"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


#creating key_pair for instance
resource "aws_key_pair" "TF_Key" {
  key_name   = "TF_Key"
 public_key = tls_private_key.rsa.public_key_openssh
 }

# RSA key of size 4096 bits
resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#create file ans store key
resource "local_file" "TF_Key" {
  content  = tls_private_key.rsa.private_key_pem
  filename = "TF_Key.pem"
}



#creating aws instance
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

#creating first instance for Webserver (public)
resource "aws_instance" "WebServer" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.webserver.id]
  subnet_id              = aws_subnet.awslab-subnet-public.id
  key_name               = "TF_Key"
  associate_public_ip_address="true"
  root_block_device {  
    volume_size = 8
  }
 
 #installing Dockr and Docker-compose in the instance using user-data
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update
    sudo apt install snapd
    sudo snap install docker  
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    sudo curl -L https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  EOF

  tags = {
    Name = "WebServer"
  }
}

#creating second instance (database Private)
resource "aws_instance" "DataBase" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.database.id]
  subnet_id              = aws_subnet.awslab-subnet-private.id
  key_name               = "TF_Key"
  associate_public_ip_address  =  false
  root_block_device {  
    volume_size = 8
  }

  #installing Dockr and Docker-compose in the instance using user-data
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update
    sudo apt install snapd
    sudo snap install docker  
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    sudo curl -L https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  EOF

  tags = {
    Name = "DataBase"
  }
}
