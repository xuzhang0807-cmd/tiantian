# TianTian Ops - WordPress Docker Compose Template
services:
  wordpress:
    image: wordpress:latest
    container_name: tt-{{NAME}}
    restart: unless-stopped
    ports:
      - '127.0.0.1:{{PORT}}:80'
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: '{{DB_PASSWORD}}'
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_HOME','https://{{DOMAIN}}');
        define('WP_SITEURL','https://{{DOMAIN}}');
    volumes:
      - ./data:/var/www/html
      - ./logs:/var/log/apache2
    depends_on:
      - db
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '3'

  db:
    image: mariadb:10.11
    container_name: tt-{{NAME}}-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: '{{DB_ROOT_PASSWORD}}'
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: '{{DB_PASSWORD}}'
    volumes:
      - ./data/db:/var/lib/mysql
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '3'
