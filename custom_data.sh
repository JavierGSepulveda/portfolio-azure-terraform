#!/bin/bash
apt update -y
apt install -y nginx
systemctl start nginx
systemctl enable nginx
echo "<h1>Portafolio de Javier - desplegado con Terraform en Azure</h1>" > /var/www/html/index.html