services:
  db:
    image: mariadb:10.11
    container_name: {{NAME}}-db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${WORDPRESS_DB_NAME:-wordpress}
      MYSQL_USER: ${WORDPRESS_DB_USER:-wordpress}
      MYSQL_PASSWORD: ${DB_PASSWORD:?set DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:?set DB_ROOT_PASSWORD}
    volumes:
      - ./data/db:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    container_name: {{NAME}}
    restart: unless-stopped
    depends_on:
      - db
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: ${WORDPRESS_DB_NAME:-wordpress}
      WORDPRESS_DB_USER: ${WORDPRESS_DB_USER:-wordpress}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD:?set DB_PASSWORD}
    ports:
      - "127.0.0.1:{{WEB_PORT}}:80"
    volumes:
      - ./data:/var/www/html
      - ./logs:/var/log/apache2
