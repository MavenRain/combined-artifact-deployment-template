provider "aws" {
  region = "us-west-2"
}

locals {
  availability-zones = ["us-west-2a", "us-west-2b", "us-west-2c"],
  artifact-bucket = "oni-build-deploy"
  artifact-key = "artifact"
  artifact-acl = "public-read"
  app-name = "hello-server"
}

data "aws_availability_zones" "all" {}

resource "aws_vpc" "oni" {
  cidr_block = "192.168.0.0/16"
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.oni.id}"
}

resource "aws_route" "internet_access" {
  route_table_id = "${aws_vpc.oni.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.default.id}"
}

resource "aws_security_group" "de" {
  vpc_id      = "${aws_vpc.oni.id}"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "public-1" {
  availability_zone = "${element(local.availability-zones, 0)}"
  cidr_block = "192.168.0.0/24"
  map_public_ip_on_launch = true
  vpc_id = "${aws_vpc.oni.id}"
}

resource "aws_subnet" "public-2" {
  availability_zone = "${element(local.availability-zones, 1)}"
  cidr_block = "192.168.1.0/24"
  map_public_ip_on_launch = true
  vpc_id = "${aws_vpc.oni.id}"
}

resource "aws_subnet" "public-3" {
  availability_zone = "${element(local.availability-zones, 2)}"
  cidr_block = "192.168.2.0/24"
  map_public_ip_on_launch = true
  vpc_id = "${aws_vpc.oni.id}"
}

data "aws_ami" "ubuntu-1604" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_s3_bucket" "mojave" {
  bucket = "${local.artifact-bucket}"
  acl    = "${local.artifact-acl}"
}

resource "aws_s3_bucket_object" "object" {
  acl = "${local.artifact-acl}"
  bucket = "${aws_s3_bucket.mojave.bucket}"
  key = "${local.artifact-key}"
  source = "./${local.app-name}"
  etag = "${md5(file("./${local.app-name}"))}"
  content_type = "application/octet-stream"
}

data "template_file" "user_data" {
  template = "${file("install.sh")}"
  vars {
    bucket = "${local.artifact-bucket}"
    key = "${local.artifact-key}"
  }
}

resource "aws_launch_configuration" "example" {
  image_id               = "${data.aws_ami.ubuntu-1604.id}"
  instance_type          = "t3.nano"
  security_groups        = ["${aws_security_group.de.id}"]
  key_name               = "oni-key-3"
  user_data = "${data.template_file.user_data.rendered}"
  lifecycle {
    create_before_destroy = true
  }
  depends_on = ["aws_s3_bucket_object.object"]
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = "${aws_launch_configuration.example.id}"
  vpc_zone_identifier = ["${aws_subnet.public-1.id}","${aws_subnet.public-2.id}", "${aws_subnet.public-3.id}"]
  min_size = 3
  max_size = 6
  load_balancers = ["${aws_elb.example.name}"]
  health_check_type = "ELB"
  tag {
    key = "Name"
    value = "terraform-autoscaling-group-template"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "elb" {
  vpc_id = "${aws_vpc.oni.id}"
  name = "terraform-example-elb"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "example" {
  name = "terraform-asg-example"
  security_groups = ["${aws_security_group.elb.id}"]
  subnets = ["${aws_subnet.public-1.id}", "${aws_subnet.public-2.id}", "${aws_subnet.public-3.id}"]
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:8080/"
  }
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "8080"
    instance_protocol = "http"
  }
  depends_on = ["aws_s3_bucket_object.object"]
}

output "elb_dns_name" {
  value = "${aws_elb.example.dns_name}"
}
